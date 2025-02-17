// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/MultiTokenFeeDistributor.sol";
import "src/Interfaces/IMultiTokenFeeDistributor.sol";
import "src/VeToken.sol";
import "src/test/SampleToken.sol";
import "script/DeployMultiTokenFeeDistributor.s.sol";

contract MultiTokenFeeDistributor_FirstClaimTest is Test, DeployMultiTokenFeeDistributor {
    uint256 constant DAY = 86400;
    uint256 constant WEEK = DAY * 7;
    uint256 constant amount = 1e18 * 1000; // 1000 tokens
    uint256 constant THREE_MONTHS = 12 weeks;

    uint256 createTime;
    address admin = address(0x1);
    address emergencyReturn = address(0x2);
    address user1 = address(0x3);
    address user2 = address(0x4);

    IMultiTokenFeeDistributor public feeDistributor;
    VeToken veToken;
    SampleToken rewardToken1;
    SampleToken rewardToken2;
    SampleToken rewardToken3;
    SampleToken stakeToken;

    uint256 startTimeToken1;
    uint256 startTimeToken2;

    function setUp() public {
        // Initialize tokens
        rewardToken1 = new SampleToken(1e26);
        rewardToken2 = new SampleToken(1e26);
        rewardToken3 = new SampleToken(1e26);
        stakeToken = new SampleToken(1e26);

        // Initialize the veToken
        veToken = new VeToken(address(stakeToken), "veToken", "veTKN");

        vm.startPrank(admin);
        (address proxyAddress,) = deploy(address(veToken), admin, emergencyReturn, false);
        feeDistributor = IMultiTokenFeeDistributor(proxyAddress);
        vm.stopPrank();

        // Lock user tokens in veToken
        createTime = vm.getBlockTimestamp() + 100 * WEEK;
        stakeToken.transfer(user1, amount);
        vm.prank(user1);
        stakeToken.approve(address(veToken), amount);
        vm.prank(user1);
        veToken.createLock(amount, createTime);

        // Admin adds rewardToken with a start time of 3 months from now
        vm.prank(admin);
        feeDistributor.addToken(address(rewardToken1), vm.getBlockTimestamp() + THREE_MONTHS);
        vm.prank(admin);
        feeDistributor.addToken(address(rewardToken2), vm.getBlockTimestamp() + THREE_MONTHS);

        startTimeToken1 = feeDistributor.startTime(address(rewardToken1));
        startTimeToken2 = feeDistributor.startTime(address(rewardToken2));

        vm.prank(admin);
        feeDistributor.toggleAllowCheckpointToken();
    }

    function testCannotClaimRewardToken1BeforeThreeMonths() public {
        // Send some reward tokens to the distributor contract
        rewardToken1.transfer(address(feeDistributor), 1e18 * 100);

        // Warp to 2 months later (before the reward distribution start time)
        vm.warp(startTimeToken1 - 4 weeks);

        // User tries to claim but should fail because 3 months haven't passed yet
        vm.prank(user1);
        uint256 claimedAmount = feeDistributor.claim(address(rewardToken1));
        assertTrue(
            claimedAmount == 0, "User should not be able to claim tokens before the reward distribution start time"
        );

        // Warp to 3 months later (after the reward distribution start time)
        vm.warp(startTimeToken1 + 2 weeks);

        // User claims and should succeed
        vm.prank(user1);
        claimedAmount = feeDistributor.claim(address(rewardToken1));
        assertApproxEqAbs(
            claimedAmount, 1e18 * 100, 1e4, "Claim should be approximately 1e18 * 100 tokens after 3 months"
        );
    }

    function testCanClaimRewardToken1AfterThreeMonths() public {
        // Send some reward tokens to the distributor contract
        rewardToken1.transfer(address(feeDistributor), 1e18 * 100);

        // Warp to 3 months later (after the reward distribution start time)
        vm.warp(startTimeToken1 + 2 weeks);

        // User claims and should succeed
        vm.prank(user1);
        uint256 claimedAmount = feeDistributor.claim(address(rewardToken1));

        assertApproxEqAbs(
            claimedAmount, 1e18 * 100, 1e4, "Claim should be approximately 1e18 * 100 tokens after 3 months"
        );
    }

    function testClaimRewardToken1WithNewLock() public {
        // Send some reward tokens to the distributor contract
        rewardToken1.transfer(address(feeDistributor), 1e18 * 100);

        vm.warp(startTimeToken1 + 1 weeks);
        vm.prank(user1);
        feeDistributor.claim(address(rewardToken1));
        stakeToken.transfer(user2, amount);
        vm.prank(user2);
        stakeToken.approve(address(veToken), amount);
        vm.prank(user2);
        veToken.createLock(amount, createTime);

        feeDistributor.timeCursor();
        feeDistributor.lastCheckpointTotalSupplyTime();

        // Warp to 3 months later (after the reward distribution start time)
        vm.warp(startTimeToken1 + 2 weeks);

        rewardToken1.transfer(address(feeDistributor), 1e18 * 100);

        // User1 claims
        vm.prank(user1);
        uint256 claimedAmountUser1 = feeDistributor.claim(address(rewardToken1));

        // User2 claims
        vm.prank(user2);
        uint256 claimedAmountUser2 = feeDistributor.claim(address(rewardToken1));

        // Check the distribution
        assertApproxEqAbs(
            claimedAmountUser1, 1e18 * 50, 1e4, "User1 should have claimed approximately 50% of the tokens"
        );
        assertApproxEqAbs(
            claimedAmountUser2, 1e18 * 50, 1e4, "User2 should have claimed approximately 50% of the tokens"
        );
    }

    function testClaimRewardToken1WithLateLock() public {
        // Send some reward tokens to the distributor contract
        rewardToken1.transfer(address(feeDistributor), 1e18 * 100);

        // Warp to 3 months later (after the reward distribution start time)
        vm.warp(startTimeToken1 + 1 weeks);

        // User2 creates a new lock after the start time
        stakeToken.transfer(user2, amount);
        vm.prank(user2);
        stakeToken.approve(address(veToken), amount);
        vm.prank(user2);
        veToken.createLock(amount, vm.getBlockTimestamp() + 30 * WEEK);

        // User2 tries to claim but should fail because the lock was created after the start time
        vm.prank(user2);
        uint256 claimedAmountUser2 = feeDistributor.claim(address(rewardToken1));
        assertTrue(claimedAmountUser2 == 0, "User2 should not have claimed any tokens");
    }

    function testCannotClaimMultipleTokensBeforeThreeMonths() public {
        // Send some reward tokens to the distributor contract
        rewardToken1.transfer(address(feeDistributor), 1e18 * 100);
        rewardToken2.transfer(address(feeDistributor), 1e18 * 100);

        // Warp to 2 months later (before the reward distribution start time)
        // solhint-disable-next-line security/no-block-members
        vm.warp(startTimeToken1 - 4 weeks);

        // User tries to claim but should fail because 3 months haven't passed yet
        vm.startPrank(user1);
        uint256 claimedAmount1 = feeDistributor.claim(address(rewardToken1));
        uint256 claimedAmount2 = feeDistributor.claim(address(rewardToken2));
        assertTrue(
            claimedAmount1 == 0,
            "User should not be able to claim rewardToken1 before the reward distribution start time"
        );
        assertTrue(
            claimedAmount2 == 0,
            "User should not be able to claim rewardToken2 before the reward distribution start time"
        );

        // Warp to 3 months later (after the reward distribution start time)
        // solhint-disable-next-line security/no-block-members
        vm.warp(startTimeToken1 + 2 weeks);

        // User claims and should succeed
        vm.startPrank(user1);
        claimedAmount1 = feeDistributor.claim(address(rewardToken1));
        claimedAmount2 = feeDistributor.claim(address(rewardToken2));
        assertApproxEqAbs(
            claimedAmount1,
            1e18 * 100,
            1e4,
            "Claim for rewardToken1 should be approximately 1e18 * 100 tokens after 3 months"
        );
        assertApproxEqAbs(
            claimedAmount2,
            1e18 * 100,
            1e4,
            "Claim for rewardToken2 should be approximately 1e18 * 100 tokens after 3 months"
        );
    }

    function testCanClaimMultipleTokensAfterThreeMonths() public {
        // Send some reward tokens to the distributor contract
        rewardToken1.transfer(address(feeDistributor), 1e18 * 100);
        rewardToken2.transfer(address(feeDistributor), 1e18 * 100);

        // Warp to 3 months later (after the reward distribution start time)
        // solhint-disable-next-line security/no-block-members
        vm.warp(startTimeToken1 + 2 weeks);

        // User claims and should succeed
        vm.startPrank(user1);
        uint256 claimedAmount1 = feeDistributor.claim(address(rewardToken1));
        uint256 claimedAmount2 = feeDistributor.claim(address(rewardToken2));

        assertApproxEqAbs(
            claimedAmount1,
            1e18 * 100,
            1e4,
            "Claim for rewardToken1 should be approximately 1e18 * 100 tokens after 3 months"
        );
        assertApproxEqAbs(
            claimedAmount2,
            1e18 * 100,
            1e4,
            "Claim for rewardToken2 should be approximately 1e18 * 100 tokens after 3 months"
        );
    }

    // コメント: 複数のトークンを請求するテスト
    function testMultiTokenClaim() public {
        rewardToken1.transfer(address(feeDistributor), 1e18);
        rewardToken2.transfer(address(feeDistributor), 1e18);

        vm.warp(startTimeToken1 + 1 weeks);
        vm.prank(user1);
        uint256 claimedAmount1 = feeDistributor.claim(address(rewardToken1));
        assertApproxEqAbs(
            claimedAmount1,
            1e18,
            1e4,
            "User should be able to claim approximately 1e18 tokens of rewardToken1 after 1 week"
        );

        vm.warp(startTimeToken1 + 19 weeks);
        vm.prank(user1);
        uint256 claimedAmount2 = feeDistributor.claim(address(rewardToken2));
        assertApproxEqAbs(
            claimedAmount2,
            1e18,
            1e4,
            "User should be able to claim approximately 1e18 tokens of rewardToken2 after 19 weeks"
        );

        rewardToken1.transfer(address(feeDistributor), 1e18);

        vm.warp(startTimeToken1 + 24 weeks);
        vm.prank(user1);
        claimedAmount1 = feeDistributor.claim(address(rewardToken1));
        assertApproxEqAbs(
            claimedAmount1,
            1e18,
            1e4,
            "User should be able to claim approximately 1e18 tokens of rewardToken1 after 24 weeks"
        );
    }

    // コメント: 複数のトークンを20週以上空けて請求するシナリオのテスト
    function testMultiTokenClaim2() public {
        rewardToken1.transfer(address(feeDistributor), 1e18);
        rewardToken2.transfer(address(feeDistributor), 1e18);

        vm.warp(startTimeToken1 + 1 weeks);
        vm.prank(user1);
        uint256 claimedAmount1 = feeDistributor.claim(address(rewardToken1));
        assertApproxEqAbs(
            claimedAmount1,
            1e18,
            1e4,
            "User should be able to claim approximately 1e18 tokens of rewardToken1 after 1 week"
        );

        vm.warp(startTimeToken1 + 22 weeks);
        vm.prank(user1);
        uint256 claimedAmount2 = feeDistributor.claim(address(rewardToken2));
        assertApproxEqAbs(
            claimedAmount2,
            1e18,
            1e4,
            "User should be able to claim approximately 1e18 tokens of rewardToken2 after 22 weeks"
        );

        rewardToken1.transfer(address(feeDistributor), 1e18);

        vm.warp(startTimeToken1 + 43 weeks);
        vm.prank(user1);
        claimedAmount1 = feeDistributor.claim(address(rewardToken1));
        assertApproxEqAbs(
            claimedAmount1,
            1e18,
            1e4,
            "User should be able to claim approximately 1e18 tokens of rewardToken1 after 43 weeks"
        );
    }

    // コメント: オーナーが0週目と22週目にリワードトークンを投入し、ユーザが30週目にclaimを実行するテスト
    function testOwnerDepositsAndUserClaims() public {
        vm.warp(startTimeToken1);
        // 0週目にリワードトークンを投入し、tokenCheckpointを実行
        rewardToken1.transfer(address(feeDistributor), 1e18);
        vm.prank(admin);
        feeDistributor.checkpointToken(address(rewardToken1));

        // 22週目にリワードトークンを投入し、tokenCheckpointを実行
        vm.warp(startTimeToken1 + 22 * WEEK);
        rewardToken1.transfer(address(feeDistributor), 1e18);
        vm.prank(admin);
        feeDistributor.checkpointToken(address(rewardToken1));

        // 30週目にユーザがclaimを実行
        vm.warp(startTimeToken1 + 8 * WEEK);
        vm.prank(user1);
        uint256 claimedAmount = feeDistributor.claim(address(rewardToken1));
        assertApproxEqAbs(
            claimedAmount, 2e18, 1e4, "User should be able to claim approximately 2e18 tokens after 30 weeks"
        );
    }

    // コメント: オーナーが0週目と22週目に複数のリワードトークンを投入し、ユーザが30週目にclaimを実行するテスト
    function testOwnerDepositsAndUserClaimsMultipleTokens() public {
        vm.warp(startTimeToken1);
        // 0週目にリワードトークンを投入し、tokenCheckpointを実行
        rewardToken1.transfer(address(feeDistributor), 1e18);
        rewardToken2.transfer(address(feeDistributor), 1e18);
        vm.prank(admin);
        feeDistributor.checkpointToken(address(rewardToken1));
        vm.prank(admin);
        feeDistributor.checkpointToken(address(rewardToken2));

        // 22週目にリワードトークンを投入し、tokenCheckpointを実行
        vm.warp(startTimeToken1 + 22 * WEEK);
        rewardToken1.transfer(address(feeDistributor), 1e18);
        rewardToken2.transfer(address(feeDistributor), 1e18);
        vm.prank(admin);
        feeDistributor.checkpointToken(address(rewardToken1));
        vm.prank(admin);
        feeDistributor.checkpointToken(address(rewardToken2));

        // 30週目にユーザがclaimを実行
        vm.warp(startTimeToken1 + 30 * WEEK);
        vm.startPrank(user1);
        uint256 claimedAmount1 = feeDistributor.claim(address(rewardToken1));
        uint256 claimedAmount2 = feeDistributor.claim(address(rewardToken2));
        assertApproxEqAbs(
            claimedAmount1,
            2e18,
            1e4,
            "User should be able to claim approximately 2e18 tokens of rewardToken1 after 30 weeks"
        );
        assertApproxEqAbs(
            claimedAmount2,
            2e18,
            1e4,
            "User should be able to claim approximately 2e18 tokens of rewardToken2 after 30 weeks"
        );
    }

    // コメント: rewardToken2は少しタイミングをずらしてcheckpointTokenとtransferを行うテスト
    function testOwnerDepositsAndUserClaimsWithStaggeredCheckpoints() public {
        vm.warp(startTimeToken1);
        // 0週目にリワードトークンを投入し、tokenCheckpointを実行
        rewardToken1.transfer(address(feeDistributor), 1e18);
        vm.prank(admin);
        feeDistributor.checkpointToken(address(rewardToken1));

        // 0週目に少し遅れてrewardToken2を投入し、tokenCheckpointを実行
        vm.warp(startTimeToken2 + 2 * WEEK);
        rewardToken2.transfer(address(feeDistributor), 1e18);
        vm.prank(admin);
        feeDistributor.checkpointToken(address(rewardToken2));

        // 22週目にリワードトークンを投入し、tokenCheckpointを実行
        vm.warp(startTimeToken1 + 22 * WEEK);
        rewardToken1.transfer(address(feeDistributor), 1e18);
        vm.prank(admin);
        feeDistributor.checkpointToken(address(rewardToken1));

        // 22週目に少し遅れてrewardToken2を投入し、tokenCheckpointを実行
        vm.warp(startTimeToken2 + 24 * WEEK);
        rewardToken2.transfer(address(feeDistributor), 1e18);
        vm.prank(admin);
        feeDistributor.checkpointToken(address(rewardToken2));

        // 30週目にユーザがclaimを実行
        vm.warp(startTimeToken1 + 30 * WEEK);
        vm.startPrank(user1);
        uint256 claimedAmount1 = feeDistributor.claim(address(rewardToken1));
        uint256 claimedAmount2 = feeDistributor.claim(address(rewardToken2));
        assertApproxEqAbs(
            claimedAmount1,
            2e18,
            1e4,
            "User should be able to claim approximately 2e18 tokens of rewardToken1 after 30 weeks"
        );
        assertApproxEqAbs(
            claimedAmount2,
            2e18,
            1e4,
            "User should be able to claim approximately 2e18 tokens of rewardToken2 after 30 weeks"
        );
    }

    function testCanClaimRewardToken3AfterThreeYears() public {
        stakeToken.transfer(user2, amount);
        vm.prank(user2);
        stakeToken.approve(address(veToken), amount);
        vm.prank(user2);
        veToken.createLock(amount, vm.getBlockTimestamp() + 4 * 365 days);

        // 3年後にwarp
        vm.warp(vm.getBlockTimestamp() + 3 * 365 days);

        // rewardToken3を追加
        vm.prank(admin);
        feeDistributor.addToken(address(rewardToken3), vm.getBlockTimestamp());

        // rewardToken3をディストリビューターに送信
        rewardToken3.transfer(address(feeDistributor), 1e18 * 100);

        vm.warp(feeDistributor.startTime(address(rewardToken3)) + 1 weeks);

        // ユーザがclaimを実行
        vm.prank(user2);
        uint256 claimedAmount = feeDistributor.claim(address(rewardToken3));

        // 期待されるトークン量を検証
        assertApproxEqAbs(
            claimedAmount,
            1e18 * 100,
            1e4,
            "User should be able to claim approximately 1e18 * 100 tokens of rewardToken3 after 3 years"
        );
    }

    function testCanClaimRewardToken3AfterThreeYearsWithDelay() public {
        stakeToken.transfer(user2, amount);
        vm.prank(user2);
        stakeToken.approve(address(veToken), amount);
        vm.prank(user2);
        veToken.createLock(amount, vm.getBlockTimestamp() + 4 * 365 days);

        // 3年後にwarp
        vm.warp(vm.getBlockTimestamp() + 3 * 365 days);

        // rewardToken3を追加
        vm.prank(admin);
        feeDistributor.addToken(address(rewardToken3), vm.getBlockTimestamp());

        // 3年+22週間後に、rewardToken3をディストリビューターに送信
        vm.warp(feeDistributor.startTime(address(rewardToken3)) + 22 weeks);
        rewardToken3.transfer(address(feeDistributor), 1e18 * 100);

        // ユーザがclaimを実行
        vm.prank(user2);
        uint256 claimedAmount = feeDistributor.claim(address(rewardToken3));

        // 期待されるトークン量を検証
        assertApproxEqAbs(
            claimedAmount,
            1e18 * 100,
            1e4,
            "User should be able to claim approximately 1e18 * 100 tokens of rewardToken3 after 3 years"
        );
    }
}
