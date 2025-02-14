// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {FlexStake} from "../src/FlexStake.sol";
import {Error} from "../src/errors/Error.sol";
import "./mocks/MockToken.sol";
import "./mocks/MockStakingHook.sol";
import "./mocks/MockProxy.sol";

contract FlexStakeTest is Test {
    FlexStake public staking;
    MockToken public token;
    MockStakingHook public hook;

    address public owner;
    address public user1;
    address public user2;
    address public penaltyRecipient;

    uint256 public constant INITIAL_BALANCE = 1000000 ether;
    uint256 public constant MIN_STAKE = 100 ether;
    uint256 public constant MAX_STAKE = 1000 ether;
    uint256 public constant MIN_LOCK = 7 days;
    uint256 public constant MAX_LOCK = 365 days;
    uint256 public constant PENALTY_PERCENTAGE = 1000; // 10%

    event OptionCreated(uint256 indexed id, FlexStake.Option option);
    event StakeCreated(
        uint256 indexed optionId, address indexed staker, uint256 amount, uint256 lockDuration, uint256 stakeId
    );
    event StakeExtended(uint256 indexed optionId, address indexed staker, uint256 newLockDuration);
    event Withdraw(uint256 indexed optionId, address indexed staker, uint256 amount, bool penaltyApplied);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        penaltyRecipient = makeAddr("penaltyRecipient");

        vm.startPrank(owner);

        // Deploy implementation
        FlexStake implementation = new FlexStake();

        // Create initialization data
        bytes memory initData = abi.encodeWithSelector(FlexStake.initialize.selector, owner);

        // Deploy proxy
        MockProxy proxy = new MockProxy(address(implementation), initData);

        // Set up the main contract reference
        staking = FlexStake(address(proxy));

        token = new MockToken();
        hook = new MockStakingHook();

        vm.stopPrank();

        // Setup initial balances
        token.mint(user1, INITIAL_BALANCE);
        token.mint(user2, INITIAL_BALANCE);

        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);

        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);
    }

    function test_Initialize() public view {
        assertEq(staking.owner(), owner);
        assertEq(staking.nextOptionId(), 1);
        assertEq(staking.emergencyPaused(), false);
    }

    function test_CreateBasicOption() public {
        vm.startPrank(owner);

        FlexStake.Option memory option = FlexStake.Option({
            id: 1,
            isLocked: true,
            minLockDuration: MIN_LOCK,
            maxLockDuration: MAX_LOCK,
            hasEarlyExitPenalty: true,
            penaltyPercentage: PENALTY_PERCENTAGE,
            penaltyRecipient: penaltyRecipient,
            minStakeAmount: MIN_STAKE,
            maxStakeAmount: MAX_STAKE,
            hasLinearVesting: false,
            vestingStart: 0,
            vestingCliff: 0,
            vestingDuration: 0,
            baseMultiplier: 10000,
            hasTimeBasedMultiplier: false,
            multiplierIncreaseRate: 0,
            token: address(token),
            requiresData: false,
            hookContract: address(0)
        });

        vm.expectEmit(true, true, true, true);
        emit OptionCreated(1, option);

        uint256 optionId = staking.createOption(option);
        assertEq(optionId, 1);

        FlexStake.Option memory createdOption = staking.getOption(optionId);
        assertEq(createdOption.isLocked, option.isLocked);
        assertEq(createdOption.minLockDuration, option.minLockDuration);
        assertEq(createdOption.maxLockDuration, option.maxLockDuration);
        assertEq(createdOption.token, option.token);

        vm.stopPrank();
    }

    function test_CreateOptionWithHooks() public {
        vm.startPrank(owner);

        FlexStake.Option memory option = FlexStake.Option({
            id: 1,
            isLocked: true,
            minLockDuration: MIN_LOCK,
            maxLockDuration: MAX_LOCK,
            hasEarlyExitPenalty: true,
            penaltyPercentage: PENALTY_PERCENTAGE,
            penaltyRecipient: penaltyRecipient,
            minStakeAmount: MIN_STAKE,
            maxStakeAmount: MAX_STAKE,
            hasLinearVesting: false,
            vestingStart: 0,
            vestingCliff: 0,
            vestingDuration: 0,
            baseMultiplier: 10000,
            hasTimeBasedMultiplier: false,
            multiplierIncreaseRate: 0,
            token: address(token),
            requiresData: true,
            hookContract: address(hook)
        });

        uint256 optionId = staking.createOption(option);
        assertEq(optionId, 1);

        vm.stopPrank();
    }

    function test_BasicStaking() public {
        // Create option
        vm.prank(owner);
        uint256 optionId = _createBasicOption();

        // Stake tokens
        vm.startPrank(user1);
        uint256 stakeAmount = 500 ether;
        uint256 lockDuration = 30 days;

        vm.expectEmit(true, true, true, true);
        emit StakeCreated(optionId, user1, stakeAmount, lockDuration, 2);

        staking.stake(optionId, stakeAmount, lockDuration, "");

        // Verify stake
        FlexStake.Stake memory initialStake = staking.getStake(optionId, user1);
        assertEq(initialStake.amount, stakeAmount);
        assertEq(initialStake.lockDuration, lockDuration);

        FlexStake.Stake memory hookStake = staking.getStake(optionId, user1);
        assertEq(hookStake.amount, stakeAmount);
        assertEq(hookStake.data, "");

        vm.stopPrank();
    }

    function test_StakingWithHooks() public {
        vm.prank(owner);
        uint256 optionId = _createOptionWithHooks();

        vm.startPrank(user1);
        uint256 stakeAmount = 500 ether;
        uint256 lockDuration = 30 days;
        bytes memory data = abi.encode("test data");

        staking.stake(optionId, stakeAmount, lockDuration, data);

        FlexStake.Stake memory initialStake = staking.getStake(optionId, user1);
        assertEq(initialStake.amount, stakeAmount);
        assertEq(initialStake.data, data);

        FlexStake.Stake memory hookStake = staking.getStake(optionId, user1);
        assertEq(hookStake.amount, stakeAmount);
        assertEq(hookStake.data, data);

        vm.stopPrank();
    }

    function test_ExtendStake() public {
        vm.prank(owner);
        uint256 optionId = _createBasicOption();

        // Initial stake
        vm.startPrank(user1);
        uint256 stakeAmount = 500 ether;
        uint256 initialLockDuration = 30 days;
        staking.stake(optionId, stakeAmount, initialLockDuration, "");

        // Extend stake
        uint256 additionalDuration = 30 days;
        vm.expectEmit(true, true, true, true);
        emit StakeExtended(optionId, user1, initialLockDuration + additionalDuration);

        staking.extendStake(optionId, additionalDuration);

        FlexStake.Stake memory stake = staking.getStake(optionId, user1);
        assertEq(stake.lockDuration, initialLockDuration + additionalDuration);
        assertEq(stake.amount, stakeAmount); // Amount should remain unchanged

        vm.stopPrank();
    }

    function test_WithdrawAfterLockPeriod() public {
        vm.prank(owner);
        uint256 optionId = _createBasicOption();

        // Stake tokens
        vm.startPrank(user1);
        uint256 stakeAmount = 500 ether;
        uint256 lockDuration = 30 days;
        staking.stake(optionId, stakeAmount, lockDuration, "");

        // Move time forward past lock period
        vm.warp(block.timestamp + lockDuration + 1);

        uint256 balanceBefore = token.balanceOf(user1);
        uint256 expectedAmount = stakeAmount - ((stakeAmount * PENALTY_PERCENTAGE) / 10000); // Account for 10% penalty

        staking.withdraw(optionId);

        assertEq(token.balanceOf(user1), balanceBefore + expectedAmount);

        FlexStake.Stake memory stake = staking.getStake(optionId, user1);
        assertEq(stake.amount, 0);

        vm.stopPrank();
    }

    function test_RevertWithdrawBeforeLockPeriod() public {
        vm.prank(owner);
        uint256 optionId = _createBasicOption();

        // Stake tokens
        vm.startPrank(user1);
        uint256 stakeAmount = 500 ether;
        uint256 lockDuration = 30 days;
        staking.stake(optionId, stakeAmount, lockDuration, "");

        // Try to withdraw before lock period ends
        vm.expectRevert(Error.WithdrawBeforeLockPeriod.selector);
        staking.withdraw(optionId);

        vm.stopPrank();
    }

    function test_EmergencyPause() public {
        vm.prank(owner);
        uint256 optionId = _createBasicOption();

        // Stake tokens
        vm.startPrank(user1);
        uint256 stakeAmount = 500 ether;
        uint256 lockDuration = 30 days;
        staking.stake(optionId, stakeAmount, lockDuration, "");
        vm.stopPrank();

        // Enable emergency pause
        vm.prank(owner);
        staking.setEmergencyPause(true);

        // Try operations while paused
        vm.startPrank(user1);
        vm.expectRevert(Error.EmergencyPauseActive.selector);
        staking.stake(optionId, stakeAmount, lockDuration, "");

        vm.expectRevert(Error.EmergencyPauseActive.selector);
        staking.withdraw(optionId);

        vm.expectRevert(Error.EmergencyPauseActive.selector);
        staking.extendStake(optionId, 30 days);
        vm.stopPrank();
    }

    function test_CreateOptionWithVesting() public {
        vm.startPrank(owner);

        FlexStake.Option memory option = FlexStake.Option({
            id: 1,
            isLocked: true,
            minLockDuration: MIN_LOCK,
            maxLockDuration: MAX_LOCK,
            hasEarlyExitPenalty: true,
            penaltyPercentage: PENALTY_PERCENTAGE,
            penaltyRecipient: penaltyRecipient,
            minStakeAmount: MIN_STAKE,
            maxStakeAmount: MAX_STAKE,
            hasLinearVesting: true,
            vestingStart: block.timestamp,
            vestingCliff: 30 days,
            vestingDuration: 180 days,
            baseMultiplier: 10000,
            hasTimeBasedMultiplier: false,
            multiplierIncreaseRate: 0,
            token: address(token),
            requiresData: false,
            hookContract: address(0)
        });

        uint256 optionId = staking.createOption(option);
        assertEq(optionId, 1);

        vm.stopPrank();
    }

    function test_CreateOptionWithTimeMultiplier() public {
        vm.startPrank(owner);

        FlexStake.Option memory option = FlexStake.Option({
            id: 1,
            isLocked: true,
            minLockDuration: MIN_LOCK,
            maxLockDuration: MAX_LOCK,
            hasEarlyExitPenalty: false,
            penaltyPercentage: 0,
            penaltyRecipient: address(0),
            minStakeAmount: MIN_STAKE,
            maxStakeAmount: MAX_STAKE,
            hasLinearVesting: false,
            vestingStart: 0,
            vestingCliff: 0,
            vestingDuration: 0,
            baseMultiplier: 10000,
            hasTimeBasedMultiplier: true,
            multiplierIncreaseRate: 100,
            token: address(token),
            requiresData: false,
            hookContract: address(0)
        });

        uint256 optionId = staking.createOption(option);
        assertEq(optionId, 1);

        vm.stopPrank();
    }

    function test_FlexibleStaking() public {
        vm.startPrank(owner);
        FlexStake.Option memory option = FlexStake.Option({
            id: 1,
            isLocked: false,
            minLockDuration: 0,
            maxLockDuration: 0,
            hasEarlyExitPenalty: false,
            penaltyPercentage: 0,
            penaltyRecipient: address(0),
            minStakeAmount: MIN_STAKE,
            maxStakeAmount: MAX_STAKE,
            hasLinearVesting: false,
            vestingStart: 0,
            vestingCliff: 0,
            vestingDuration: 0,
            baseMultiplier: 10000,
            hasTimeBasedMultiplier: false,
            multiplierIncreaseRate: 0,
            token: address(token),
            requiresData: false,
            hookContract: address(0)
        });
        uint256 optionId = staking.createOption(option);
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 stakeAmount = 500 ether;
        staking.stake(optionId, stakeAmount, 0, "");

        // Can withdraw immediately in flexible staking
        staking.withdraw(optionId);
        vm.stopPrank();
    }

    // todo: fix this test
    // function test_VestingWithdraw() public {
    //     // Set initial block timestamp
    //     vm.warp(1000);
    //     uint256 startTime = block.timestamp;

    //     vm.startPrank(owner);
    //     FlexStake.Option memory option = FlexStake.Option({
    //         isLocked: true,
    //         minLockDuration: 180 days,
    //         maxLockDuration: 365 days,
    //         hasEarlyExitPenalty: false,
    //         penaltyPercentage: 0,
    //         penaltyRecipient: address(0),
    //         minStakeAmount: MIN_STAKE,
    //         maxStakeAmount: MAX_STAKE,
    //         hasLinearVesting: true,
    //         vestingStart: startTime,
    //         vestingCliff: 30 days,
    //         vestingDuration: 180 days,
    //         baseMultiplier: 10000,
    //         hasTimeBasedMultiplier: false,
    //         multiplierIncreaseRate: 0,
    //         token: address(token),
    //         paused: false,
    //         requiresData: false,
    //         hookContract: address(0)
    //     });
    //     uint256 optionId = staking.createOption(option);
    //     vm.stopPrank();

    //     vm.startPrank(user1);
    //     uint256 stakeAmount = 500 ether;

    //     // Initial stake
    //     staking.stake(optionId, stakeAmount, 180 days, "");

    //     // Try withdraw before cliff
    //     vm.warp(startTime + 15 days);
    //     vm.expectRevert(Error.ExceedsWithdrawableAmount.selector);
    //     staking.withdrawPartial(optionId, 1 ether);

    //     // Move to 50% vesting (90 days = half of 180 days)
    //     vm.warp(startTime + 90 days);
    //     uint256 expectedVested = (stakeAmount * 90 days) / 180 days;
    //     uint256 withdrawAmount = expectedVested / 2; // Withdraw half of vested amount

    //     uint256 balanceBefore = token.balanceOf(user1);
    //     staking.withdrawPartial(optionId, withdrawAmount);
    //     assertEq(token.balanceOf(user1) - balanceBefore, withdrawAmount);

    //     // Verify remaining stake
    //     FlexStake.Stake memory stake = staking.getStake(optionId, user1);
    //     assertEq(stake.amount, stakeAmount - withdrawAmount);

    //     // Move past vesting period and withdraw remaining
    //     vm.warp(startTime + 181 days);
    //     balanceBefore = token.balanceOf(user1);
    //     staking.withdraw(optionId);
    //     assertEq(token.balanceOf(user1) - balanceBefore, stakeAmount - withdrawAmount);

    //     vm.stopPrank();
    // }

    function test_BatchOperations() public {
        vm.startPrank(owner);
        uint256[] memory optionIds = new uint256[](2);
        optionIds[0] = _createBasicOption();
        optionIds[1] = _createOptionWithHooks();
        vm.stopPrank();

        vm.startPrank(user1);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 300 ether;
        amounts[1] = 400 ether;

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 30 days;
        lockDurations[1] = 60 days;

        bytes[] memory datas = new bytes[](2);
        datas[0] = "";
        datas[1] = abi.encode("test data");

        // Batch stake
        staking.batchStake(optionIds, amounts, lockDurations, datas);

        // Batch extend
        uint256[] memory additionalDurations = new uint256[](2);
        additionalDurations[0] = 30 days;
        additionalDurations[1] = 30 days;
        staking.batchExtendStake(optionIds, additionalDurations);

        // Move time forward
        vm.warp(block.timestamp + 91 days);

        // Batch withdraw
        staking.batchWithdraw(optionIds);
        vm.stopPrank();
    }

    function test_StakeMigration() public {
        vm.startPrank(owner);
        uint256 fromOptionId = _createFlexibleOption();
        uint256 toOptionId = _createFlexibleOption();
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 stakeAmount = 500 ether;
        staking.stake(fromOptionId, stakeAmount, 0, "");
        staking.migrateStake(fromOptionId, toOptionId);
        vm.stopPrank();
    }

    function test_BatchStakeMigration() public {
        vm.startPrank(owner);
        uint256[] memory fromOptionIds = new uint256[](2);
        uint256[] memory toOptionIds = new uint256[](2);
        fromOptionIds[0] = _createFlexibleOption();
        fromOptionIds[1] = _createFlexibleOption();
        toOptionIds[0] = _createFlexibleOption();
        toOptionIds[1] = _createFlexibleOption();
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 stakeAmount = 500 ether;
        staking.stake(fromOptionIds[0], stakeAmount, 0, "");
        staking.stake(fromOptionIds[1], stakeAmount, 0, "");
        staking.batchMigrateStake(fromOptionIds, toOptionIds);
        vm.stopPrank();
    }

    function test_PauseAndRelease() public {
        vm.prank(owner);
        uint256 optionId = _createBasicOption();

        // Stake tokens
        vm.startPrank(user1);
        uint256 stakeAmount = 500 ether;
        uint256 lockDuration = 30 days;
        staking.stake(optionId, stakeAmount, lockDuration, "");

        // Try withdraw before lock period (should fail)
        vm.expectRevert(Error.WithdrawBeforeLockPeriod.selector);
        staking.withdraw(optionId);
        vm.stopPrank();

        // Pause and release
        vm.prank(owner);
        staking.pauseAndRelease(optionId);

        // Now withdraw should work even before lock period
        vm.startPrank(user1);
        uint256 balanceBefore = token.balanceOf(user1);
        staking.withdraw(optionId);

        // Should get full amount back (no penalty)
        assertEq(token.balanceOf(user1), balanceBefore + stakeAmount);
        vm.stopPrank();
    }

    function test_PauseAndReleaseAlreadyPaused() public {
        vm.startPrank(owner);
        uint256 optionId = _createBasicOption();
        staking.pauseStaking(optionId);
        staking.pauseAndRelease(optionId);
        vm.stopPrank();

        bool isPaused = staking.pausedOptions(optionId);
        bool isReleased = staking.releasedOptions(optionId);
        assertEq(isPaused, true);
        assertEq(isReleased, true);
    }

    // Helper function for flexible option
    function _createFlexibleOption() internal returns (uint256) {
        FlexStake.Option memory option = FlexStake.Option({
            id: 1,
            isLocked: false,
            minLockDuration: 0,
            maxLockDuration: 0,
            hasEarlyExitPenalty: false,
            penaltyPercentage: 0,
            penaltyRecipient: address(0),
            minStakeAmount: MIN_STAKE,
            maxStakeAmount: MAX_STAKE,
            hasLinearVesting: false,
            vestingStart: 0,
            vestingCliff: 0,
            vestingDuration: 0,
            baseMultiplier: 10000,
            hasTimeBasedMultiplier: false,
            multiplierIncreaseRate: 0,
            token: address(token),
            requiresData: false,
            hookContract: address(0)
        });

        return staking.createOption(option);
    }

    // Helper functions
    function _createBasicOption() internal returns (uint256) {
        FlexStake.Option memory option = FlexStake.Option({
            id: 1,
            isLocked: true,
            minLockDuration: MIN_LOCK,
            maxLockDuration: MAX_LOCK,
            hasEarlyExitPenalty: true,
            penaltyPercentage: PENALTY_PERCENTAGE,
            penaltyRecipient: penaltyRecipient,
            minStakeAmount: MIN_STAKE,
            maxStakeAmount: MAX_STAKE,
            hasLinearVesting: false,
            vestingStart: 0,
            vestingCliff: 0,
            vestingDuration: 0,
            baseMultiplier: 10000,
            hasTimeBasedMultiplier: false,
            multiplierIncreaseRate: 0,
            token: address(token),
            requiresData: false,
            hookContract: address(0)
        });

        return staking.createOption(option);
    }

    function _createOptionWithHooks() internal returns (uint256) {
        FlexStake.Option memory option = FlexStake.Option({
            id: 1,
            isLocked: true,
            minLockDuration: MIN_LOCK,
            maxLockDuration: MAX_LOCK,
            hasEarlyExitPenalty: true,
            penaltyPercentage: PENALTY_PERCENTAGE,
            penaltyRecipient: penaltyRecipient,
            minStakeAmount: MIN_STAKE,
            maxStakeAmount: MAX_STAKE,
            hasLinearVesting: false,
            vestingStart: 0,
            vestingCliff: 0,
            vestingDuration: 0,
            baseMultiplier: 10000,
            hasTimeBasedMultiplier: false,
            multiplierIncreaseRate: 0,
            token: address(token),
            requiresData: true,
            hookContract: address(hook)
        });

        return staking.createOption(option);
    }
}
