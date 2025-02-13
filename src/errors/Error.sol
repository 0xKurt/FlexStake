// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Error {
    // Staking Errors
    error MinimumStakeGreaterThanZero();
    error MaxStakeGreaterThanMinStake();
    error LockedStakingMustHaveMinDuration();
    error MaxDurationGreaterThanMinDuration();
    error InvalidPenaltyPercentage();
    error PenaltyRecipientRequired();
    error FlexibleStakingCannotHaveLockPeriods();
    error FlexibleStakingCannotHavePenalty();
    error NoPenaltiesAllowedForFlexibleStaking();
    error NoPenaltyRecipientForFlexibleStaking();
    error VestingMustHaveDuration();
    error VestingMustHaveStartTime();
    error CliffMustBeLessThanOrEqualToVestingDuration();
    error NoVestingSettingsAllowed();
    error MultiplierRateMustBeGreaterThanZero();
    error NoMultiplierIncreaseRateIfDisabled();
    error InvalidStakeAmount();
    error StakeNotFound();
    error WithdrawBeforeLockPeriod();
    error InsufficientBalanceForPenalty();
    error StakingPaused();
    error DataRequired();
    error NoDataAllowed();
    error EmergencyPaused();
    error InvalidHookContract();
    error HookContractZeroAddress();
    error AlreadyPaused();
    error NotPaused();
    error EmergencyPauseActive();
    error VestingRequiresLocking();
    error VestingDurationExceedsLockDuration();
    error VestingStartTooFarInFuture();
    error BaseMultiplierTooLow();
    error LockDurationTooShortForVesting();
    error InsufficientBalance();
    error ExceedsWithdrawableAmount();
    error EmergencyPauseNotActive();
    error ArrayLengthMismatch();
    error CannotMigrateLockedStake();
}
