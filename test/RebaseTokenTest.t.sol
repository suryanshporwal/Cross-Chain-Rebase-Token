// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/Interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    uint256 constant SEND_VALUE = 1e30;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");


    function setUp() public {
        vm.startPrank(owner);
        vm.deal(owner, SEND_VALUE);
        rebaseToken = new RebaseToken();
        vault = new Vault(address(rebaseToken));
        RebaseToken(rebaseToken).grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    function testBalanceIncreasesLinearlyAfterDeposit(uint256 amount) public {
        // vm.assume(amount > 1e5); <-- we bounded the amount , instead of using assume to skip interations
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. Deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        // 2. check out rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);
        // 3. warp tht time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        // 4. warp tht time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();
    }

    function testCanRedeemInstantlyAfterDeposit(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit into the vault
        vm.startPrank(user);
        vm.deal(user, amount);
        assertEq(0, rebaseToken.balanceOf(user));
        vault.deposit{value: amount}();
        assertEq(amount, rebaseToken.balanceOf(user));
        // 2. now redeem the same amount
        vault.redeem(amount);
        assertEq(0, rebaseToken.balanceOf(user));
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max) + 1;
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, depositAmount);
        vault.deposit{value: depositAmount}();

        // 2. Time passed
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        uint256 startingEthBalance = address(user).balance;
        vm.stopPrank();

        // 3. Add the rewards to the vault
        vm.prank(owner);
        vm.deal(owner, balanceAfterSomeTime - depositAmount);
        addRewardsToVault(balanceAfterSomeTime - depositAmount);

        // 4. Redeem
        vm.startPrank(user);
        vault.redeem(depositAmount);

        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance - startingEthBalance, depositAmount);
        assertGt(balanceAfterSomeTime, depositAmount);
        vm.stopPrank();
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        // 1. deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        // 2. owner reduces the interest rate
        vm.startPrank(owner);
        rebaseToken.setInterestRate(rebaseToken.getCurrentInterestRate() - 1e10);
        console.log("current Interest rate is: ", rebaseToken.getCurrentInterestRate());
        vm.stopPrank();

        // 3. transfer
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);

        // check the user interest rate that has been inherited (5e10 -> not 4e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testCannotSetInterestRateIfNotOwner(uint256 newInterestRate, address sender) public {
        vm.assume(sender != owner);
        vm.prank(sender);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCurrentInterestRateCanNotBeIncreased(uint256 newInterestRate) public {
        newInterestRate = bound(newInterestRate, rebaseToken.getCurrentInterestRate() + 1, type(uint256).max);
        vm.prank(owner);
        vm.expectRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(20e10);
    }
}
