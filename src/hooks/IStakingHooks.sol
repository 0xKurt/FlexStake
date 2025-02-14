// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IStakingHooks
 * @notice Interface for implementing staking hooks
 * @dev Implement this interface to create custom hook logic for staking operations
 */
interface IStakingHooks is IERC165 {
    /**
     * @notice Called before a stake is created
     * @param user Address of the user staking
     * @param optionId ID of the staking option
     * @param amount Amount being staked
     * @param duration Duration of the stake lock
     * @param data Additional data for the stake
     */
    function beforeStake(address user, uint256 optionId, uint256 amount, uint256 duration, bytes calldata data) external;

    /**
     * @notice Called after a stake is created
     * @param user Address of the user staking
     * @param optionId ID of the staking option
     * @param amount Amount being staked
     * @param duration Duration of the stake lock
     * @param data Additional data for the stake
     */
    function afterStake(address user, uint256 optionId, uint256 amount, uint256 duration, bytes calldata data) external;

    /**
     * @notice Called before a withdrawal
     * @param user Address of the user withdrawing
     * @param optionId ID of the staking option
     * @param amount Amount being withdrawn
     * @param data Additional data from the stake
     */
    function beforeWithdraw(address user, uint256 optionId, uint256 amount, bytes calldata data) external;

    /**
     * @notice Called after a withdrawal
     * @param user Address of the user withdrawing
     * @param optionId ID of the staking option
     * @param amount Amount withdrawn
     * @param penaltyApplied Whether a penalty was applied
     * @param data Additional data from the stake
     */
    function afterWithdraw(address user, uint256 optionId, uint256 amount, bool penaltyApplied, bytes calldata data)
        external;

    /**
     * @notice Called before extending a stake
     * @param user Address of the user extending
     * @param optionId ID of the staking option
     * @param newDuration New total duration
     * @param data Additional data from the stake
     */
    function beforeExtend(address user, uint256 optionId, uint256 newDuration, bytes calldata data) external;

    /**
     * @notice Called after extending a stake
     * @param user Address of the user extending
     * @param optionId ID of the staking option
     * @param newDuration New total duration
     * @param data Additional data from the stake
     */
    function afterExtend(address user, uint256 optionId, uint256 newDuration, bytes calldata data) external;

    /**
     * @notice Called before unstaking
     * @param user Address of the user unstaking
     * @param stakeId ID of the stake
     * @param data Additional data from the stake
     */
    function beforeUnstake(address user, uint256 stakeId, bytes calldata data) external;

    /**
     * @notice Called after unstaking
     * @param user Address of the user unstaking
     * @param stakeId ID of the stake
     * @param data Additional data from the stake
     */
    function afterUnstake(address user, uint256 stakeId, bytes calldata data) external;
}
