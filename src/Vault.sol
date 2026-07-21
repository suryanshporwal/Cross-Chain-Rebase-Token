// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./Interfaces/IRebaseToken.sol";

contract Vault {
    // we need to pass atoken address to the constructor
    // create a deposit function that mints tokens to the user equal to the amount of ETH the user deposits
    // create a way to redeem function that burns tokens from the user and sends the user ETH
    // create a way to add rewards to the vault

    address private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(address _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    function getRebaseTokenAddress() external view returns (address) {
        return i_rebaseToken;
    }

    /**
     * @notice Allows users to deposit ETH into the vault and mint rebase tokens in return
     */

    function deposit() external payable {
        // We need to use the amount of ETH the user has sent to mint tokens to the user
        IRebaseToken(i_rebaseToken).mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function redeem(uint256 _amount) external {
        // CEI
        if (_amount == type(uint256).max) {
            _amount = IRebaseToken(i_rebaseToken).balanceOf(msg.sender);
        }
        // 1. burn the tokens from the user
        IRebaseToken(i_rebaseToken).burn(msg.sender, _amount);
        // 2. we need to tsend the user ETH
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }
}
