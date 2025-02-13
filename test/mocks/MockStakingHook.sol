// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/interfaces/IStakingHooks.sol";

contract MockStakingHook is IStakingHooks {
    bool public shouldRevert;

    event BeforeStakeCalled(address user, uint256 optionId, uint256 amount, uint256 duration, bytes data);
    event AfterStakeCalled(address user, uint256 optionId, uint256 amount, uint256 duration, bytes data);
    event BeforeWithdrawCalled(address user, uint256 optionId, uint256 amount, bytes data);
    event AfterWithdrawCalled(address user, uint256 optionId, uint256 amount, bool penaltyApplied, bytes data);
    event BeforeExtendCalled(address user, uint256 optionId, uint256 newDuration, bytes data);
    event AfterExtendCalled(address user, uint256 optionId, uint256 newDuration, bytes data);

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function beforeStake(address user, uint256 optionId, uint256 amount, uint256 duration, bytes calldata data)
        external
    {
        if (shouldRevert) revert("Hook reverted");
        emit BeforeStakeCalled(user, optionId, amount, duration, data);
    }

    function afterStake(address user, uint256 optionId, uint256 amount, uint256 duration, bytes calldata data)
        external
    {
        if (shouldRevert) revert("Hook reverted");
        emit AfterStakeCalled(user, optionId, amount, duration, data);
    }

    function beforeWithdraw(address user, uint256 optionId, uint256 amount, bytes calldata data) external {
        if (shouldRevert) revert("Hook reverted");
        emit BeforeWithdrawCalled(user, optionId, amount, data);
    }

    function afterWithdraw(address user, uint256 optionId, uint256 amount, bool penaltyApplied, bytes calldata data)
        external
    {
        if (shouldRevert) revert("Hook reverted");
        emit AfterWithdrawCalled(user, optionId, amount, penaltyApplied, data);
    }

    function beforeExtend(address user, uint256 optionId, uint256 newDuration, bytes calldata data) external {
        if (shouldRevert) revert("Hook reverted");
        emit BeforeExtendCalled(user, optionId, newDuration, data);
    }

    function afterExtend(address user, uint256 optionId, uint256 newDuration, bytes calldata data) external {
        if (shouldRevert) revert("Hook reverted");
        emit AfterExtendCalled(user, optionId, newDuration, data);
    }
}
