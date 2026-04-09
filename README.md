# Cross-chain Rebase Token

1. A protocol that allows user to deposit into a vault and in return, receive rebase tokens that represent their underlying balance.
2. Rebase token -> balanceOf function is dynamic to show the changing balance with time. 
    - Balance increase linearly with time.
    - mint tokens to our users every time they perform an action(miniting, burning, transferring, or Bridging);
3. Interest rate :
    - Individually set an interest rate or each user based on some global increase rate of the protocol at the time the user deposits into the vault.
    - This global interest rate can only decrease to incentivise/reward early adopters.
    - Increase token adoption.
