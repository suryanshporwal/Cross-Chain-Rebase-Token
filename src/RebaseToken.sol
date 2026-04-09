// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title RebaseToken
 * @author Suryansh Porwal
 * @notice This is a cross-chain rebase token that incentivises user to deposit into a vault and gain interest in form of rewards.
 * @notice The interest rate in the smart contract can only decrease.
 */

contract RebaseToken is ERC20, Ownable {
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_currentInterestRate = 5e10; // 0.00000005 %
    mapping(address user => uint256 interestAmount) private s_userInterestRate;
    mapping(address user => uint256 lastTimestamp) private s_userLastUpdatedTimestamp;

    error RebaseToken__InterestRateCanOnlyDecrease();
    error RebaseToken__AmountCantBeZero();

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate  The new interest rate to set
     * @dev The new interest rate can only increase
     */

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Set the interest rate
        if (_newInterestRate >= s_currentInterestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease();
        }
        s_currentInterestRate = _newInterestRate;
    }

    /**
     * @notice Get the principle balance of a user. This is the number of tokens that have currently been minted to the user,
     *         not including any interest that has accrued since the last time the user interacted with the protocol
     * @param _user The user to get the princple balance of
     * @return The principle balance of the user
     */

    function principleBalance(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * calculate the balance for the user including the interest that has accuulated since the last update
     * (principle balance) + some interest that has occured
     * @param _user The user to calulate the balance for
     * @return The balance of the user including the interest that has accumulated since the last update
     */

    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user( the number of tokens)
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     *
     * @notice Mint the user tokens when they deposit into the vault
     * @param _to The user to mint the tokens
     * @param _amount amount of tokens required to be minted
     */

    function mint(address _to, uint256 _amount) external {
        if (_amount <= 0) revert RebaseToken__AmountCantBeZero();
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_currentInterestRate;
        s_userLastUpdatedTimestamp[_to] = block.timestamp;
        _mint(_to, _amount);
    }

    /**
     * @notice Calculate the interest that has accumulated since the last update
     * @param _user The user to calculate the interest accumulated for
     * @return linearInterest The interest that as accumulated since the last update
     */

    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be lineaer growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of linear growth
        // (principal amount) + principal amount * user interest rate * time elapsed
        // -> so we can write it as linearInterest= principal amount(1+(interest rate * time elapsed))

        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _recipient The user to transfer the tokens to
     * @param _amount The amount of tokens to transfer
     * @return True if transfer was successful
     */

    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        if (_amount <= 0) revert RebaseToken__AmountCantBeZero();
        // CEI
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            // makes the user which has not balance rate inherit the interest rate of it's sender
            // if the user already deposits some amount already, this statement does not gets executed and new interest rate
            // will be applicable
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        } else {
            // reciever already owns some tokens so we need to apply new interest rate on whole amount, no matter what
            s_userInterestRate[_recipient] = s_currentInterestRate;
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Mint the accrued interest to the user since the last stime they interacted wiht the protocol (e.g. burn, mint, transfer)
     * @param _user The user to mint the accrued interest to
     */

    function _mintAccruedInterest(address _user) internal {
        // (1) Find their current balance of rebase tokens that have been minted to the user
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) Calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // Calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // set/update the last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease);
    }

    function burn(address _from, uint256 _amount) external {
        if (_amount == type(uint256).max) {
            // So, no dust remaining
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    // Getters
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    function getCurrentInterestRete() external view returns(uint256) {
        return s_currentInterestRate;
    }
}
