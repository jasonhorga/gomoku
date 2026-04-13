"""MCTS engine with pattern-based priors and optional neural network.

Three modes:
  1. Pure rollout MCTS (slowest, weakest) - legacy.
  2. Pattern-guided MCTS (no NN, very fast, Level-5 quality). Used to
     generate bootstrap training data and as the teacher for the CNN.
  3. NN-guided MCTS (uses CNN for priors and value). Used after bootstrap.

The pattern-guided mode is the key improvement: it gives MCTS a strong
prior (score_cell) and an instant "expert" rollout policy, so even 100-200
simulations per move produce very good play.
"""

import math
import random
import numpy as np
from ai.game_logic import GameLogic, BOARD_SIZE, EMPTY, BLACK, WHITE, DIRECTIONS
from ai.pattern_eval import score_cell, best_moves_by_score
from ai.vcf_search import find_vcf


class MCTSNode:
    __slots__ = ['parent', 'children', 'move', 'player', 'visits', 'wins',
                 'untried_moves', 'prior']

    def __init__(self, parent, move, player, prior=1.0):
        self.parent = parent
        self.children = []
        self.move = move
        self.player = player
        self.visits = 0
        self.wins = 0.0
        self.untried_moves = []
        self.prior = prior

    def puct(self, c_puct=1.4):
        """PUCT formula (AlphaZero-style) - more stable than plain UCB1
        when priors vary significantly."""
        if self.parent is None or self.parent.visits == 0:
            q = 0.0 if self.visits == 0 else self.wins / self.visits
            return q + c_puct * self.prior
        q = 0.0 if self.visits == 0 else self.wins / self.visits
        u = c_puct * self.prior * math.sqrt(self.parent.visits) / (1 + self.visits)
        return q + u

    def best_child(self, c_puct=1.4):
        return max(self.children, key=lambda c: c.puct(c_puct))

    def most_visited_child(self):
        return max(self.children, key=lambda c: c.visits)


def _softmax_prior(scores, temperature=1.0):
    """Turn raw pattern scores into a normalized prior distribution.

    Uses max-normalization (scale-invariant) instead of log1p
    compression. log1p squished the difference between "great" and
    "amazing" moves together, which made the teacher too diffuse —
    a double-threat move (score 6000) barely outranked a regular
    open-three (score 1000). After this change, the top move gets
    a strongly-peaked prior, letting MCTS focus simulations there.
    """
    if not scores:
        return {}
    arr = np.array([s for _, s in scores], dtype=np.float64)
    arr = np.maximum(arr, 0.0)
    peak = arr.max()
    if peak > 0:
        arr = arr / peak  # now in [0, 1]
    arr = arr / max(temperature, 1e-6)
    arr = arr - arr.max()  # numerical stability
    exp = np.exp(arr)
    total = exp.sum()
    if total <= 0:
        exp = np.ones_like(exp)
        total = exp.sum()
    probs = exp / total
    return {scores[i][0]: float(probs[i]) for i in range(len(scores))}


class MCTSEngine:
    def __init__(self, simulations=1000, nn_model=None, c_puct=1.4,
                 use_pattern_prior=True, dirichlet_alpha=0.0,
                 dirichlet_eps=0.25, vcf_depth=10, vcf_branch=8,
                 cnn_prior_weight=0.5):
        """
        simulations: number of MCTS rollouts per move
        nn_model: optional ModelWrapper for neural net guidance
        c_puct: PUCT exploration constant
        use_pattern_prior: when True and no nn_model, use pattern scores
                           as priors (highly recommended)
        dirichlet_alpha: if > 0, add Dirichlet(alpha) noise to root priors.
                         Use ~0.3 for self-play diversity (AlphaZero-style),
                         0.0 for deterministic evaluation play.
        dirichlet_eps: blend ratio for the noise (0.25 from AlphaZero paper).
        vcf_depth: search depth for Victory-by-Continuous-Four tactical
                   lookahead. Set 0 to disable. Default 10 finds most
                   tactical wins; branching factor is typically small (1-4
                   candidate fours per node) so it's fast.
        vcf_branch: max four-move candidates to try per VCF node.
        """
        self.simulations = simulations
        self.nn_model = nn_model
        self.c_puct = c_puct
        self.use_pattern_prior = use_pattern_prior
        self.dirichlet_alpha = dirichlet_alpha
        self.dirichlet_eps = dirichlet_eps
        self.vcf_depth = vcf_depth
        self.vcf_branch = vcf_branch
        self.cnn_prior_weight = cnn_prior_weight

    # --------------------------------------------------------------------
    # Core API
    # --------------------------------------------------------------------

    def choose_move(self, game: GameLogic) -> tuple:
        """Return (row, col) for the best move."""
        probs = self.get_move_probabilities(game)
        move_idx = int(np.argmax(probs))
        return move_idx // BOARD_SIZE, move_idx % BOARD_SIZE

    def get_move_probabilities(self, game: GameLogic) -> np.ndarray:
        """Run MCTS and return visit-count-based move probabilities (225,)."""
        candidates = game.get_nearby_moves(2)
        if not candidates:
            probs = np.zeros(BOARD_SIZE * BOARD_SIZE, dtype=np.float32)
            probs[7 * BOARD_SIZE + 7] = 1.0
            return probs

        player = game.current_player
        opponent = WHITE if player == BLACK else BLACK

        # ---- Tactical shortcut: immediate win / must-block ------------
        # If we can win in 1, just do it (skip the whole MCTS).
        for r, c in candidates:
            game.board[r][c] = player
            if game._check_win(r, c):
                game.board[r][c] = EMPTY
                probs = np.zeros(BOARD_SIZE * BOARD_SIZE, dtype=np.float32)
                probs[r * BOARD_SIZE + c] = 1.0
                return probs
            game.board[r][c] = EMPTY
        for r, c in candidates:
            game.board[r][c] = opponent
            if game._check_win(r, c):
                game.board[r][c] = EMPTY
                probs = np.zeros(BOARD_SIZE * BOARD_SIZE, dtype=np.float32)
                probs[r * BOARD_SIZE + c] = 1.0
                return probs
            game.board[r][c] = EMPTY

        # ---- VCF tactical search --------------------------------------
        # Can the current player force a win via continuous-four? Narrow
        # DFS (only four-threat moves) that's very cheap and catches most
        # tactical wins. This is what lifts play above local-greedy
        # pattern heuristics.
        if self.vcf_depth > 0:
            vcf_move = find_vcf(game.board, player,
                                max_depth=self.vcf_depth,
                                max_branch=self.vcf_branch)
            if vcf_move is not None:
                probs = np.zeros(BOARD_SIZE * BOARD_SIZE, dtype=np.float32)
                probs[vcf_move[0] * BOARD_SIZE + vcf_move[1]] = 1.0
                return probs
            # Also defend against opponent's VCF: if opponent has a forced
            # win, we must block their starting move (best effort).
            opp_vcf = find_vcf(game.board, opponent,
                               max_depth=self.vcf_depth,
                               max_branch=self.vcf_branch)
            if opp_vcf is not None:
                # Play the opponent's VCF starting square to block it.
                probs = np.zeros(BOARD_SIZE * BOARD_SIZE, dtype=np.float32)
                probs[opp_vcf[0] * BOARD_SIZE + opp_vcf[1]] = 1.0
                return probs

        # ---- Compute priors for candidates -----------------------------
        priors = self._compute_priors(game, candidates, player)

        # ---- Prune obviously bad moves ---------------------------------
        # Keep top-12 by prior; speeds up MCTS enormously on a 15x15 board.
        if len(candidates) > 12:
            scored = [(m, priors.get(m, 0.0)) for m in candidates]
            scored.sort(key=lambda x: -x[1])
            candidates = [m for m, _ in scored[:12]]
            # renormalise priors on kept moves
            total = sum(priors[m] for m in candidates) or 1.0
            priors = {m: priors[m] / total for m in candidates}

        # ---- Dirichlet noise for exploration diversity -----------------
        # AlphaZero-style: mix noise into root priors so self-play games
        # don't collapse into the same main line. Only applied when
        # dirichlet_alpha > 0 (set during self-play, not eval play).
        if self.dirichlet_alpha > 0 and len(candidates) > 1:
            noise = np.random.dirichlet(
                [self.dirichlet_alpha] * len(candidates)
            )
            eps = self.dirichlet_eps
            for i, m in enumerate(candidates):
                priors[m] = (1 - eps) * priors[m] + eps * float(noise[i])

        # ---- MCTS search ----------------------------------------------
        root = MCTSNode(None, None, opponent)
        root.untried_moves = list(candidates)
        root_priors = priors

        for _ in range(self.simulations):
            sim_game = game.copy()
            node = root

            # Selection
            while not node.untried_moves and node.children:
                node = node.best_child(self.c_puct)
                sim_game.place_stone(node.move[0], node.move[1])

            # Expansion
            if node.untried_moves and not sim_game.game_over:
                move = self._pick_untried(node, root_priors)
                node.untried_moves.remove(move)
                sim_game.place_stone(move[0], move[1])
                prior = root_priors.get(move, 1.0 / max(len(candidates), 1)) if node is root else 0.1
                child = MCTSNode(node, move, sim_game.current_player, prior)
                # For deeper nodes, compute priors locally if nearby moves exist
                if not sim_game.game_over:
                    child_cands = sim_game.get_nearby_moves(1)
                    child.untried_moves = child_cands[:8]  # tight pruning for depth
                node.children.append(child)
                node = child

            # Simulation / leaf evaluation
            if sim_game.game_over:
                # Terminal node — exact outcome
                if sim_game.winner == player:
                    result_value = 1.0
                elif sim_game.winner == EMPTY:
                    result_value = 0.0
                else:
                    result_value = -1.0
                value_is_scalar = True
            elif self.nn_model is not None and not self.use_pattern_prior:
                # Pure CNN mode: trust NN value head
                _, value = self.nn_model.predict(sim_game)
                result_value = value
                value_is_scalar = True
            elif self.use_pattern_prior:
                # Hybrid or pattern-only: continuous pattern eval.
                # _static_leaf_value returns EMPTY for most positions,
                # giving MCTS a flat 0.5 everywhere — the search tree
                # can't differentiate moves. Continuous eval (tanh of
                # pattern score diff) provides a gradient so MCTS
                # actually amplifies priors into a better policy.
                result_value = self._continuous_leaf_value(sim_game, player)
                value_is_scalar = True
            else:
                winner = self._static_leaf_value(sim_game)
                result_value = winner
                value_is_scalar = False

            # Backpropagation
            self._backprop(node, result_value, value_is_scalar, player)

        # ---- Extract visit-count policy -------------------------------
        probs = np.zeros(BOARD_SIZE * BOARD_SIZE, dtype=np.float32)
        total_visits = sum(c.visits for c in root.children)
        if total_visits > 0:
            for c in root.children:
                if c.move:
                    probs[c.move[0] * BOARD_SIZE + c.move[1]] = c.visits / total_visits
        else:
            # Fallback: use priors directly
            for m, p in priors.items():
                probs[m[0] * BOARD_SIZE + m[1]] = p
        return probs

    # --------------------------------------------------------------------
    # Helpers
    # --------------------------------------------------------------------

    def _compute_priors(self, game, candidates, player):
        """Dict (row, col) -> prior probability.

        In hybrid mode (nn_model + use_pattern_prior), blends CNN policy
        with pattern scores 50/50.  A small CNN's raw policy is noisy;
        pattern priors catch tactical threats the CNN misses.
        """
        nn_priors = None
        if self.nn_model is not None:
            try:
                policy, _ = self.nn_model.predict(game)
                nn_priors = {(r, c): float(policy[r * BOARD_SIZE + c])
                             for r, c in candidates}
                total = sum(nn_priors.values())
                if total <= 0:
                    nn_priors = None
                else:
                    nn_priors = {m: nn_priors[m] / total for m in candidates}
            except Exception:
                nn_priors = None

        pat_priors = None
        if self.use_pattern_prior:
            scored = [((r, c), score_cell(game.board, r, c, player))
                      for r, c in candidates]
            pat_priors = _softmax_prior(scored, temperature=0.3)

        # Blend when both are available (hybrid mode)
        if nn_priors is not None and pat_priors is not None:
            w = self.cnn_prior_weight
            blended = {}
            for m in candidates:
                blended[m] = w * nn_priors.get(m, 0) + (1 - w) * pat_priors.get(m, 0)
            total = sum(blended.values()) or 1.0
            return {m: blended[m] / total for m in candidates}

        if nn_priors is not None:
            return nn_priors
        if pat_priors is not None:
            return pat_priors

        uniform = 1.0 / len(candidates)
        return {m: uniform for m in candidates}

    def _pick_untried(self, node, root_priors):
        """Pick the untried move with the highest prior (not pure random)."""
        if node.parent is None:
            best = max(node.untried_moves, key=lambda m: root_priors.get(m, 0.0))
            return best
        return random.choice(node.untried_moves)

    def _backprop(self, node, result_value, value_is_scalar, perspective_player):
        while node is not None:
            node.visits += 1
            if value_is_scalar:
                # NN value: +1 good for perspective_player
                if node.player == perspective_player:
                    node.wins += (1.0 - result_value) / 2.0
                else:
                    node.wins += (1.0 + result_value) / 2.0
            else:
                winner = result_value
                if winner == node.player:
                    node.wins += 1.0
                elif winner == EMPTY:
                    node.wins += 0.5
            node = node.parent

    # --------------------------------------------------------------------
    # Rollout
    # --------------------------------------------------------------------

    def _static_leaf_value(self, game: GameLogic) -> int:
        """Cheap static leaf evaluation instead of a rollout.

        Idea: the pattern prior already drives high-quality move selection
        inside the tree. At leaves we only need a rough "who is winning
        locally" signal. A 30-step Python rollout called 2M times per move
        is the bottleneck; this O(candidates) check is 100x faster and
        preserves most of the learning signal.

        Returns BLACK / WHITE / EMPTY.
        """
        if game.game_over:
            return game.winner

        player = game.current_player
        opponent = WHITE if player == BLACK else BLACK
        candidates = game.get_nearby_moves(1)
        if not candidates:
            return EMPTY

        # Current player can win in 1?
        for r, c in candidates:
            game.board[r][c] = player
            if game._check_win(r, c):
                game.board[r][c] = EMPTY
                return player
            game.board[r][c] = EMPTY

        # Opponent can win in 1 (current player on the hook)?
        for r, c in candidates:
            game.board[r][c] = opponent
            if game._check_win(r, c):
                game.board[r][c] = EMPTY
                return opponent
            game.board[r][c] = EMPTY

        # Otherwise rely on pattern-based score
        best_self = 0.0
        best_opp = 0.0
        # Limit candidates scanned for speed
        scan = candidates if len(candidates) <= 10 else candidates[:10]
        for r, c in scan:
            s_self = score_cell(game.board, r, c, player)
            if s_self > best_self:
                best_self = s_self
            s_opp = score_cell(game.board, r, c, opponent)
            if s_opp > best_opp:
                best_opp = s_opp

        # If there's a dominant threat, resolve the leaf in its favour
        if best_opp > best_self * 1.5 and best_opp >= 1000:
            return opponent
        if best_self > best_opp * 1.5 and best_self >= 1000:
            return player
        return EMPTY

    def _continuous_leaf_value(self, game: GameLogic, perspective) -> float:
        """Continuous position evaluation for hybrid MCTS.

        Returns float in [-1, 1] from `perspective` player's point of view.
        Unlike _static_leaf_value (which returns EMPTY for most positions,
        giving MCTS a flat 0.5 signal everywhere), this uses tanh of the
        pattern-score difference to provide a *gradient* — MCTS can tell
        "this branch is slightly better" even without an immediate win.
        """
        if game.game_over:
            if game.winner == perspective:
                return 1.0
            elif game.winner == EMPTY:
                return 0.0
            else:
                return -1.0

        player = game.current_player
        opponent = WHITE if player == BLACK else BLACK
        candidates = game.get_nearby_moves(1)
        if not candidates:
            return 0.0

        # Immediate win for current player
        for r, c in candidates:
            game.board[r][c] = player
            if game._check_win(r, c):
                game.board[r][c] = EMPTY
                return 1.0 if player == perspective else -1.0
            game.board[r][c] = EMPTY

        # Immediate win for opponent (threat)
        for r, c in candidates:
            game.board[r][c] = opponent
            if game._check_win(r, c):
                game.board[r][c] = EMPTY
                return -0.8 if player == perspective else 0.8
            game.board[r][c] = EMPTY

        # Pattern score comparison — best threat for each side
        scan = candidates if len(candidates) <= 12 else candidates[:12]
        my_best = 0.0
        opp_best = 0.0
        for r, c in scan:
            s = score_cell(game.board, r, c, player)
            if s > my_best:
                my_best = s
            s = score_cell(game.board, r, c, opponent)
            if s > opp_best:
                opp_best = s

        # tanh maps score difference to [-1, 1] smoothly.
        # Scale 1000 ≈ open_three score, so having one open_three
        # advantage ≈ tanh(1) ≈ 0.76 — a clear but not decisive edge.
        diff = my_best - opp_best
        advantage = math.tanh(diff / 1000.0) * 0.8  # cap ±0.8
        if player == perspective:
            return advantage
        else:
            return -advantage
