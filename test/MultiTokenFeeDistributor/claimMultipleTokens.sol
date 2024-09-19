// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "test/util/TestBase.sol";
import "src/MultiTokenFeeDistributor.sol";
import "src/Interfaces/IMultiTokenFeeDistributor.sol";
import "src/VeToken.sol";
import "src/test/SampleToken.sol";

contract MultiTokenFeeDistributorClaimMultipleTokensTest is TestBase {
    uint256 constant DAY = 86400;
    uint256 constant WEEK = DAY * 7;
    uint256 constant amount = 1e18 * 1000; // 1000 tokens

    address alice;
    address bob;
    address charlie;

    IMultiTokenFeeDistributor public feeDistributor = IMultiTokenFeeDistributor(target);
    MultiTokenFeeDistributor distributor;
    VeToken veToken;
    IERC20 token;
    SampleToken coinA;
    SampleToken coinB;

    function setUp() public {
        alice = address(0x1);
        bob = address(0x2);
        charlie = address(0x3);

        token = new SampleToken(1e26);
        coinA = new SampleToken(1e26);
        coinB = new SampleToken(1e26);
        veToken = new VeToken(address(token), "veToken", "veTKN");
        distributor = new MultiTokenFeeDistributor();

        _use(MultiTokenFeeDistributor.initialize.selector, address(distributor));
        _use(MultiTokenFeeDistributor.addToken.selector, address(distributor));
        _use(MultiTokenFeeDistributor.checkpointTotalSupply.selector, address(distributor));
        _use(MultiTokenFeeDistributor.claimMany.selector, address(distributor));
        _use(MultiTokenFeeDistributor.checkpointToken.selector, address(distributor));
        _use(MultiTokenFeeDistributor.timeCursor.selector, address(distributor));
        _use(MultiTokenFeeDistributor.veSupply.selector, address(distributor));
        _use(MultiTokenFeeDistributor.claim.selector, address(distributor));
        _use(MultiTokenFeeDistributor.claimFor.selector, address(distributor));
        _use(MultiTokenFeeDistributor.claimMultipleTokens.selector, address(distributor));
        _use(MultiTokenFeeDistributor.lastTokenTime.selector, address(distributor));
        _use(MultiTokenFeeDistributor.toggleAllowCheckpointToken.selector, address(distributor));

        feeDistributor.initialize(address(veToken), alice, bob);

        token.transfer(alice, amount);
        token.transfer(bob, amount);
        token.transfer(charlie, amount);

        vm.prank(alice);
        token.approve(address(veToken), amount * 10);
        vm.prank(bob);
        token.approve(address(veToken), amount * 10);
        vm.prank(charlie);
        token.approve(address(veToken), amount * 10);

        vm.prank(alice);
        veToken.createLock(amount, block.timestamp + 8 * WEEK);
        vm.prank(bob);
        veToken.createLock(amount, block.timestamp + 8 * WEEK);
        vm.prank(charlie);
        veToken.createLock(amount, block.timestamp + 8 * WEEK);

        vm.warp(block.timestamp + WEEK * 5);

        coinA.transfer(address(feeDistributor), 1e18 * 10);
        coinB.transfer(address(feeDistributor), 1e18 * 10);

        vm.startPrank(alice);
        feeDistributor.addToken(address(coinA), block.timestamp);
        feeDistributor.addToken(address(coinB), block.timestamp);

        feeDistributor.checkpointToken(address(coinA));
        feeDistributor.checkpointToken(address(coinB));
        vm.warp(block.timestamp + WEEK);
        feeDistributor.checkpointToken(address(coinA));
        feeDistributor.checkpointToken(address(coinB));
    }

    function testClaimMultipleTokens() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(coinA);
        tokens[1] = address(coinB);

        uint256 balanceBeforeAliceA = coinA.balanceOf(alice);
        uint256 balanceBeforeAliceB = coinB.balanceOf(alice);

        feeDistributor.claimMultipleTokens(tokens);

        uint256 balanceAfterAliceA = coinA.balanceOf(alice);
        uint256 balanceAfterAliceB = coinB.balanceOf(alice);

        assertTrue(balanceAfterAliceA > balanceBeforeAliceA);
        assertTrue(balanceAfterAliceB > balanceBeforeAliceB);
    }

    function testClaimMultipleTokensSameAccount() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(coinA);
        tokens[1] = address(coinB);

        uint256 balanceBefore = coinA.balanceOf(alice) + coinB.balanceOf(alice);

        feeDistributor.claimMultipleTokens(tokens);

        uint256 balanceAfter = coinA.balanceOf(alice) + coinB.balanceOf(alice);

        assertTrue(balanceAfter > balanceBefore);
    }

    function testClaimMultipleTokensRevertsForInvalidToken() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(coinA);
        tokens[1] = address(coinB);
        tokens[2] = address(0x4); // Invalid token address

        vm.expectRevert("Token not found");
        feeDistributor.claimMultipleTokens(tokens);
    }
}
