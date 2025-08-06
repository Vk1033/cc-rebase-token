// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseTokenTest is Test {
    error RebaseTokenTest__FailedToSendEtherToVault();

    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));

        vm.stopPrank();
    }

    function addRewardsToVault(uint256 amount) public {
        // send some rewards to the vault using the receive function
        vm.deal(owner, amount);
        vm.prank(owner);
        (bool success,) = address(vault).call{value: amount}("");
        if (!success) {
            revert RebaseTokenTest__FailedToSendEtherToVault();
        }
    }

    function testDepositLinear(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, depositAmount);
        vault.deposit{value: depositAmount}();

        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("User's balance after deposit:", startBalance);
        assertEq(startBalance, depositAmount, "User's balance should equal the deposit amount");

        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("User's balance after 1 hour:", middleBalance);
        assertGt(middleBalance, startBalance, "User's balance should increase after 1 hour");

        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("User's balance after 2 hours:", endBalance);
        assertGt(endBalance, middleBalance, "User's balance should increase after 2 hours");

        assertApproxEqAbs(
            endBalance - middleBalance,
            middleBalance - startBalance,
            1,
            "Balance increase should be approximately linear over time"
        );

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 redeemAmount) public {
        redeemAmount = bound(redeemAmount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, redeemAmount);
        vault.deposit{value: redeemAmount}();
        assertEq(rebaseToken.balanceOf(user), redeemAmount, "User's balance should equal the deposit amount");

        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0, "User's balance should be zero after redeeming all tokens");
        assertEq(address(user).balance, redeemAmount, "User's Ether balance should equal the redeemed amount");

        vm.stopPrank();
    }

    function testRedeemAfterTimeHasPassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max); // this is a crazy number of years - 2^96 seconds is a lot
        depositAmount = bound(depositAmount, 1e5, type(uint96).max); // this is an Ether value of max 2^78 which is crazy

        // Deposit funds
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        // check the balance has increased after some time has passed
        vm.warp(time);

        // Get balance after time has passed
        uint256 balance = rebaseToken.balanceOf(user);

        // Add rewards to the vault

        addRewardsToVault(balance - depositAmount);

        // Redeem funds
        vm.prank(user);
        vault.redeem(balance);

        uint256 ethBalance = address(user).balance;

        assertEq(balance, ethBalance);
        assertGt(balance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.prank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        // Transfer some tokens to another user
        address recipient = makeAddr("recipient");
        uint256 recipientBalanceBefore = rebaseToken.balanceOf(recipient);
        uint256 userBalanceBefore = rebaseToken.balanceOf(user);
        assertEq(userBalanceBefore, amount, "User's balance should equal the deposit amount");
        assertEq(recipientBalanceBefore, 0, "Recipient's balance should be zero before transfer");

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10); // Set interest rate for testing

        vm.prank(user);
        rebaseToken.transfer(recipient, amountToSend);
        uint256 recipientBalanceAfter = rebaseToken.balanceOf(recipient);
        uint256 userBalanceAfter = rebaseToken.balanceOf(user);

        assertEq(recipientBalanceAfter, amountToSend, "Recipient's balance should equal the transferred amount");
        assertEq(userBalanceAfter, amount - amountToSend, "User's balance should decrease by the transferred amount");

        // Check that the interest rate is updated for both users
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        uint256 recipientInterestRate = rebaseToken.getUserInterestRate(recipient);
        assertEq(userInterestRate, 5e10, "User's interest rate should be updated to the new rate");
        assertEq(recipientInterestRate, 5e10, "Recipient's interest rate should be updated to the new rate");
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        newInterestRate = bound(newInterestRate, 1e8, type(uint96).max);

        vm.startPrank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
        vm.stopPrank();
    }

    function testCannotCallMintAndBurnFunctions() public {
        vm.startPrank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, 100, rebaseToken.getInterestRate());
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, 100);
        vm.stopPrank();
    }

    function testGetPrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(
            rebaseToken.principleBalanceOf(user), amount, "User's principal balance should equal the deposit amount"
        );

        vm.warp(block.timestamp + 1 hours);
        assertEq(
            rebaseToken.principleBalanceOf(user), amount, "User's principal balance should remain constant over time"
        );
    }

    function testGetRebaseTokenAddress() public view {
        address rebaseTokenAddress = vault.getRebaseToken();
        assertEq(rebaseTokenAddress, address(rebaseToken), "Vault should return the correct rebase token address");
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.Rebase__InterestCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(newInterestRate);
        uint256 finalInterestRate = rebaseToken.getInterestRate();
        assertEq(finalInterestRate, initialInterestRate, "Interest rate should not change if new rate is not lower");
    }

    function testMintAndBurnRoles() public {
        address newAccount = makeAddr("newAccount");
        vm.prank(owner);
        rebaseToken.grantMintAndBurnRole(newAccount);
        assertTrue(
            rebaseToken.hasRole(rebaseToken.getMintAndBurnRole(), newAccount),
            "New account should have mint and burn role"
        );

        vm.startPrank(newAccount);
        rebaseToken.mint(newAccount, 100, rebaseToken.getInterestRate());
        assertEq(rebaseToken.balanceOf(newAccount), 100, "New account should have 100 tokens after minting");

        rebaseToken.burn(newAccount, 100);
        assertEq(rebaseToken.balanceOf(newAccount), 0, "New account should have 0 tokens after burning");

        vm.stopPrank();
    }

    ////////////////////////
    // AI Generated Tests //
    ////////////////////////
    function testRedeemFailsWhenVaultHasInsufficientETH() public {
        uint256 depositAmount = 1 ether;

        // User deposits ETH
        vm.startPrank(user);
        vm.deal(user, depositAmount);
        vault.deposit{value: depositAmount}();
        vm.stopPrank();

        // Simulate vault losing some ETH (maybe sent elsewhere)
        vm.deal(address(vault), depositAmount - 0.5 ether);

        // User tries to redeem but vault doesn't have enough ETH
        vm.startPrank(user);
        vm.expectRevert(Vault.Vault__RedeemFailed.selector);
        vault.redeem(type(uint256).max);
        vm.stopPrank();
    }

    // ...existing code...

    function testTransferToZeroAddressFails() public {
        uint256 amount = 1 ether;
        address spender = makeAddr("spender");

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        rebaseToken.approve(spender, amount);
        vm.stopPrank();

        // Test direct transfer to zero address
        vm.prank(user);
        vm.expectRevert();
        rebaseToken.transfer(address(0), amount);

        // Test transferFrom to zero address
        vm.prank(spender);
        vm.expectRevert();
        rebaseToken.transferFrom(user, address(0), amount);
    }

    function testTransferFromWithInfiniteAllowance() public {
        uint256 amount = 2 ether;
        uint256 transferAmount = 1 ether;
        address spender = makeAddr("spender");

        // User deposits tokens
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        // User approves spender with max allowance (infinite)
        rebaseToken.approve(spender, type(uint256).max);
        vm.stopPrank();

        // Spender transfers on behalf of user
        address recipient = makeAddr("recipient");
        vm.startPrank(spender);

        uint256 allowanceBefore = rebaseToken.allowance(user, spender);
        assertEq(allowanceBefore, type(uint256).max, "Should have infinite allowance");

        rebaseToken.transferFrom(user, recipient, transferAmount);

        uint256 allowanceAfter = rebaseToken.allowance(user, spender);
        assertEq(allowanceAfter, type(uint256).max, "Infinite allowance should remain unchanged");

        vm.stopPrank();
    }

    function testTransferFromWithInsufficientAllowance() public {
        uint256 amount = 2 ether;
        uint256 allowanceAmount = 0.5 ether;
        uint256 transferAmount = 1 ether;
        address spender = makeAddr("spender");

        // User deposits tokens
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        // User approves spender with insufficient allowance
        rebaseToken.approve(spender, allowanceAmount);
        vm.stopPrank();

        // Spender tries to transfer more than allowed
        address recipient = makeAddr("recipient");
        vm.startPrank(spender);
        vm.expectRevert();
        rebaseToken.transferFrom(user, recipient, transferAmount);
        vm.stopPrank();
    }

    function testTransferFromWithZeroAmount() public {
        uint256 amount = 2 ether;
        address spender = makeAddr("spender");

        // User deposits tokens
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        // User approves spender
        rebaseToken.approve(spender, amount);
        vm.stopPrank();

        // Spender transfers zero amount
        address recipient = makeAddr("recipient");
        vm.startPrank(spender);

        uint256 userBalanceBefore = rebaseToken.balanceOf(user);
        uint256 recipientBalanceBefore = rebaseToken.balanceOf(recipient);

        rebaseToken.transferFrom(user, recipient, 0);

        uint256 userBalanceAfter = rebaseToken.balanceOf(user);
        uint256 recipientBalanceAfter = rebaseToken.balanceOf(recipient);

        assertEq(userBalanceAfter, userBalanceBefore, "User balance should not change");
        assertEq(recipientBalanceAfter, recipientBalanceBefore, "Recipient balance should not change");

        vm.stopPrank();
    }

    function testTransferFromUpdatesInterestRatesAndAllowance() public {
        uint256 amount = 2 ether;
        uint256 transferAmount = 1 ether;
        address spender = makeAddr("spender");
        address recipient = makeAddr("recipient");

        // User deposits tokens (gets 5e10 rate)
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        vm.stopPrank();

        // Set a new interest rate to 4e10
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // User approves spender
        vm.prank(user);
        rebaseToken.approve(spender, transferAmount);

        // Check balances and allowance before transfer
        uint256 userBalanceBefore = rebaseToken.balanceOf(user);
        uint256 recipientBalanceBefore = rebaseToken.balanceOf(recipient);
        uint256 allowanceBefore = rebaseToken.allowance(user, spender);

        // Spender transfers on behalf of user
        vm.prank(spender);
        rebaseToken.transferFrom(user, recipient, transferAmount);

        // Check balances and allowance changed correctly
        uint256 userBalanceAfter = rebaseToken.balanceOf(user);
        uint256 recipientBalanceAfter = rebaseToken.balanceOf(recipient);
        uint256 allowanceAfter = rebaseToken.allowance(user, spender);

        assertEq(userBalanceAfter, userBalanceBefore - transferAmount, "User balance should decrease");
        assertEq(recipientBalanceAfter, recipientBalanceBefore + transferAmount, "Recipient balance should increase");
        assertEq(allowanceAfter, allowanceBefore - transferAmount, "Allowance should decrease");

        // Check that interest rates are updated for both users
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        uint256 recipientInterestRate = rebaseToken.getUserInterestRate(recipient);

        // User keeps their original rate (5e10)
        assertEq(userInterestRate, 5e10, "User's interest rate should remain at original rate");
        // Recipient inherits sender's rate (5e10), NOT the current global rate (4e10)
        assertEq(recipientInterestRate, 5e10, "Recipient should inherit sender's interest rate");
    }

    // ...existing code...

    function testTransferMaxAmount() public {
        uint256 amount = 2 ether;

        // User deposits tokens
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        address recipient = makeAddr("recipient");
        uint256 userBalanceBefore = rebaseToken.balanceOf(user);
        uint256 recipientBalanceBefore = rebaseToken.balanceOf(recipient);

        // Transfer max amount (type(uint256).max) - this should hit the uncovered branch
        rebaseToken.transfer(recipient, type(uint256).max);

        uint256 userBalanceAfter = rebaseToken.balanceOf(user);
        uint256 recipientBalanceAfter = rebaseToken.balanceOf(recipient);

        assertEq(userBalanceAfter, 0, "User should have no tokens left");
        assertEq(
            recipientBalanceAfter, recipientBalanceBefore + userBalanceBefore, "Recipient should receive all tokens"
        );

        vm.stopPrank();
    }

    function testTransferFromMaxAmount() public {
        uint256 amount = 2 ether;
        address spender = makeAddr("spender");

        // User deposits tokens
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        // User approves spender for max amount
        rebaseToken.approve(spender, type(uint256).max);
        vm.stopPrank();

        // Spender transfers max amount on behalf of user
        address recipient = makeAddr("recipient");
        vm.startPrank(spender);

        uint256 userBalanceBefore = rebaseToken.balanceOf(user);
        uint256 recipientBalanceBefore = rebaseToken.balanceOf(recipient);

        // TransferFrom with max amount - this should hit the uncovered branch in transferFrom
        rebaseToken.transferFrom(user, recipient, type(uint256).max);

        uint256 userBalanceAfter = rebaseToken.balanceOf(user);
        uint256 recipientBalanceAfter = rebaseToken.balanceOf(recipient);

        assertEq(userBalanceAfter, 0, "User should have no tokens left");
        assertEq(
            recipientBalanceAfter, recipientBalanceBefore + userBalanceBefore, "Recipient should receive all tokens"
        );

        vm.stopPrank();
    }
}
