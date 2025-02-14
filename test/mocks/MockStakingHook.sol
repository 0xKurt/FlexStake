// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/hooks/BaseStakingHooks.sol";

contract MockStakingHook is BaseStakingHooks {
    bool public shouldRevert;

    event BeforeStakeCalled(address user, uint256 optionId, uint256 amount, uint256 duration, bytes data);
    event AfterStakeCalled(address user, uint256 optionId, uint256 amount, uint256 duration, bytes data);
    event BeforeUnstakeCalled(address user, uint256 stakeId, bytes data);
    event AfterUnstakeCalled(address user, uint256 stakeId, bytes data);

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function _beforeStake(address user, uint256 optionId, uint256 amount, uint256 duration, bytes calldata data)
        internal
        override
    {
        if (shouldRevert) revert("MockStakingHook: revert requested");
        emit BeforeStakeCalled(user, optionId, amount, duration, data);
    }

    function _afterStake(address user, uint256 optionId, uint256 amount, uint256 duration, bytes calldata data)
        internal
        override
    {
        if (shouldRevert) revert("MockStakingHook: revert requested");
        emit AfterStakeCalled(user, optionId, amount, duration, data);
    }

    function _beforeUnstake(address user, uint256 stakeId, bytes calldata data) internal override {
        if (shouldRevert) revert("MockStakingHook: revert requested");
        emit BeforeUnstakeCalled(user, stakeId, data);
    }

    function _afterUnstake(address user, uint256 stakeId, bytes calldata data) internal override {
        if (shouldRevert) revert("MockStakingHook: revert requested");
        emit AfterUnstakeCalled(user, stakeId, data);
    }

    // Implement required functions from IStakingHooks
    function beforeWithdraw(address user, uint256 optionId, uint256 amount, bytes calldata data) external {
        // Mock implementation
    }

    function afterWithdraw(address user, uint256 optionId, uint256 amount, bool penaltyApplied, bytes calldata data)
        external
    {
        // Mock implementation
    }

    function beforeExtend(address user, uint256 optionId, uint256 newDuration, bytes calldata data) external {
        // Mock implementation
    }

    function afterExtend(address user, uint256 optionId, uint256 newDuration, bytes calldata data) external {
        // Mock implementation
    }
}
