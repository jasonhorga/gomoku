"""Training loop for the Gomoku CNN."""

import torch
import torch.nn.functional as F
import numpy as np


class Trainer:
    def __init__(self, model_wrapper, lr=0.001, weight_decay=1e-4):
        self.model = model_wrapper
        self.optimizer = torch.optim.Adam(
            model_wrapper.model.parameters(),
            lr=lr,
            weight_decay=weight_decay
        )

    def train_on_data(self, training_data: list, epochs: int = 10,
                      batch_size: int = 64, on_progress=None) -> dict:
        """
        Train the model on self-play data.
        training_data: list of (state_tensor, mcts_probs, value)
        Returns: dict with loss history
        """
        self.model.train_mode()
        device = self.model.device

        # Prepare tensors
        states = np.array([d[0] for d in training_data], dtype=np.float32)
        policies = np.array([d[1] for d in training_data], dtype=np.float32)
        values = np.array([d[2] for d in training_data], dtype=np.float32)

        states_t = torch.from_numpy(states).to(device)
        policies_t = torch.from_numpy(policies).to(device)
        values_t = torch.from_numpy(values).unsqueeze(1).to(device)

        n_samples = len(training_data)
        history = {"policy_loss": [], "value_loss": [], "total_loss": []}

        for epoch in range(epochs):
            # Shuffle
            indices = torch.randperm(n_samples)
            epoch_policy_loss = 0.0
            epoch_value_loss = 0.0
            n_batches = 0

            for start in range(0, n_samples, batch_size):
                end = min(start + batch_size, n_samples)
                batch_idx = indices[start:end]

                batch_states = states_t[batch_idx]
                batch_policies = policies_t[batch_idx]
                batch_values = values_t[batch_idx]

                # Forward
                log_policy, value = self.model.model(batch_states)

                # Policy loss: cross-entropy with MCTS probabilities
                policy_loss = -torch.mean(torch.sum(batch_policies * log_policy, dim=1))

                # Value loss: MSE
                value_loss = F.mse_loss(value, batch_values)

                # Total loss
                loss = policy_loss + value_loss

                # Backward
                self.optimizer.zero_grad()
                loss.backward()
                self.optimizer.step()

                epoch_policy_loss += policy_loss.item()
                epoch_value_loss += value_loss.item()
                n_batches += 1

            avg_policy = epoch_policy_loss / max(n_batches, 1)
            avg_value = epoch_value_loss / max(n_batches, 1)
            history["policy_loss"].append(avg_policy)
            history["value_loss"].append(avg_value)
            history["total_loss"].append(avg_policy + avg_value)

            if on_progress:
                on_progress(epoch + 1, epochs, avg_policy + avg_value)

        self.model.eval_mode()
        return history
