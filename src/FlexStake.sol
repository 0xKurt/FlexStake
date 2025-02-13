// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IStakingHooks.sol";
import "./errors/Error.sol";

/**
 * @title FlexStake Contract
 * @notice A flexible staking contract that supports multiple staking options with various features
 * including locking, vesting, penalties, and hooks.
 * @dev This contract allows creation and management of different staking options with customizable parameters
 * @custom:security-contact security@flexstake.example.com
 */
contract StakingContract is Error, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct Option {
        bool isLocked;
        uint256 minLockDuration;
        uint256 maxLockDuration;
        bool hasEarlyExitPenalty;
        uint256 penaltyPercentage;
        address penaltyRecipient;
        uint256 minStakeAmount;
        uint256 maxStakeAmount;
        bool hasLinearVesting;
        uint256 vestingStart;
        uint256 vestingCliff;
        uint256 vestingDuration;
        uint256 baseMultiplier;
        bool hasTimeBasedMultiplier;
        uint256 multiplierIncreaseRate;
        address token;
        bool paused;
        bool requiresData;
        address hookContract;
    }

    struct Stake {
        uint256 amount;
        uint256 lockDuration;
        uint256 creationTime;
        uint256 lastExtensionTime;
        bytes data;
    }

    mapping(uint256 => Option) public options;
    mapping(uint256 => mapping(address => Stake)) public stakes;
    uint256 public nextOptionId;

    // Events
    event OptionCreated(uint256 indexed id, Option option);
    event StakeCreated(
        uint256 indexed optionId, address indexed staker, uint256 amount, uint256 lockDuration, uint256 stakeId
    );
    event StakeExtended(uint256 indexed optionId, address indexed staker, uint256 newLockDuration);
    event Withdraw(uint256 indexed optionId, address indexed staker, uint256 amount, bool penaltyApplied);
    event OptionPaused(uint256 indexed optionId);
    event OptionUnpaused(uint256 indexed optionId);
    event StakingOperations(
        address indexed user, uint256 indexed optionId, uint256 amount, uint256 duration, bytes32 operationType
    );
    event EmergencyWithdraw(uint256 indexed optionId, address indexed staker, uint256 amount);
    event StakeMigrated(
        uint256 indexed fromOptionId, uint256 indexed toOptionId, address indexed staker, uint256 amount
    );
    event BatchStakeCreated(uint256[] optionIds, address indexed staker, uint256[] amounts, uint256[] lockDurations);
    event BatchStakeExtended(uint256[] optionIds, address indexed staker, uint256[] newLockDurations);
    event BatchWithdraw(uint256[] optionIds, address indexed staker, uint256[] amounts, bool[] penaltiesApplied);
    event BatchStakeMigrated(uint256[] fromOptionIds, uint256[] toOptionIds, address indexed staker, uint256[] amounts);

    // State variables for emergency pause
    bool public emergencyPaused;

    // Batch events
    bytes32 private constant OPERATION_STAKE = keccak256("STAKE");
    bytes32 private constant OPERATION_WITHDRAW = keccak256("WITHDRAW");
    bytes32 private constant OPERATION_EXTEND = keccak256("EXTEND");

    /**
     * @dev Modifier to prevent reentrancy in functions that interact with hooks
     */
    modifier nonReentrantHooks() {
        if (emergencyPaused) revert EmergencyPauseActive();
        _;
    }

    /**
     * @dev Emergency pause modifier
     */
    modifier whenNotEmergencyPaused() {
        if (emergencyPaused) revert EmergencyPaused();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract replacing the constructor
     * @param _owner The address that will own the contract
     */
    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        nextOptionId = 1;
        emergencyPaused = false;
    }

    /**
     * @notice Checks if a stake requires additional data
     * @param optionId The ID of the staking option
     * @return bool True if the stake requires additional data
     */
    function requiresStakeData(uint256 optionId) external view returns (bool) {
        return options[optionId].requiresData;
    }

    /**
     * @notice Emergency pause all contract operations
     * @dev Only callable by contract owner
     */
    function setEmergencyPause(bool _paused) external onlyOwner {
        emergencyPaused = _paused;
    }

    function _validateHookContract(address hookContract) internal {
        if (hookContract == address(0)) revert HookContractZeroAddress();

        // Check if contract exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(hookContract)
        }
        if (codeSize == 0) revert InvalidHookContract();

        // Optionally check interface implementation
        try IStakingHooks(hookContract).beforeStake{gas: 50000}(address(0), 0, 0, 0, "") {
            // Success is fine for mock
        } catch {
            // Failure is also fine
        }
    }

    // Option Management Functions
    function createOption(Option calldata option) external onlyOwner returns (uint256) {
        if (option.hookContract != address(0)) {
            _validateHookContract(option.hookContract);
        }

        _validateBasicParams(option);
        _validateLockingParams(option);
        _validateVestingParams(option);
        _validateMultiplierParams(option);

        uint256 optionId;
        unchecked {
            optionId = nextOptionId++;
        }

        options[optionId] = option;
        options[optionId].paused = false; // Ensure new options start unpaused

        emit OptionCreated(optionId, options[optionId]);
        return optionId;
    }

    function pauseStaking(uint256 optionId) external onlyOwner {
        Option storage option = options[optionId];
        if (option.paused) revert AlreadyPaused();
        option.paused = true;
        emit OptionPaused(optionId);
    }

    function unpauseStaking(uint256 optionId) external onlyOwner {
        Option storage option = options[optionId];
        if (!option.paused) revert NotPaused();
        option.paused = false;
        emit OptionUnpaused(optionId);
    }

    // Staking Functions
    function stake(uint256 optionId, uint256 amount, uint256 lockDuration, bytes calldata data)
        external
        nonReentrantHooks
        whenNotEmergencyPaused
    {
        _stake(optionId, amount, lockDuration, data);
    }

    function _stake(uint256 optionId, uint256 amount, uint256 lockDuration, bytes calldata data) internal {
        Option storage option = options[optionId];
        address hookAddr = option.hookContract;

        if (option.requiresData && data.length == 0) revert DataRequired();
        if (!option.requiresData && data.length > 0) revert NoDataAllowed();

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).beforeStake(msg.sender, optionId, amount, lockDuration, data);
        }

        if (option.paused) revert StakingPaused();
        if (amount < option.minStakeAmount || (option.maxStakeAmount > 0 && amount > option.maxStakeAmount)) {
            revert InvalidStakeAmount();
        }

        if (option.isLocked) {
            if (lockDuration < option.minLockDuration || lockDuration > option.maxLockDuration) {
                revert InvalidStakeAmount();
            }
        } else {
            if (lockDuration != 0) {
                revert FlexibleStakingCannotHaveLockPeriods();
            }
        }

        if (option.hasLinearVesting) {
            if (block.timestamp + lockDuration < option.vestingStart + option.vestingDuration) {
                revert LockDurationTooShortForVesting();
            }
        }

        IERC20 token = IERC20(option.token);
        token.safeTransferFrom(msg.sender, address(this), amount);

        stakes[optionId][msg.sender] = Stake({
            amount: amount,
            lockDuration: lockDuration,
            creationTime: block.timestamp,
            lastExtensionTime: block.timestamp,
            data: data
        });

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).afterStake(msg.sender, optionId, amount, lockDuration, data);
        }

        emit StakeCreated(optionId, msg.sender, amount, lockDuration, nextOptionId);

        emit StakingOperations(msg.sender, optionId, amount, lockDuration, OPERATION_STAKE);
    }

    function extendStake(uint256 optionId, uint256 additionalLockDuration)
        external
        nonReentrantHooks
        whenNotEmergencyPaused
    {
        _extendStake(optionId, additionalLockDuration);
    }

    function _extendStake(uint256 optionId, uint256 additionalLockDuration) internal {
        Option storage option = options[optionId];
        if (option.paused) revert StakingPaused();

        Stake storage userStake = stakes[optionId][msg.sender];
        address hookAddr = option.hookContract;

        if (userStake.amount == 0) revert StakeNotFound();

        uint256 newLockDuration = userStake.lockDuration + additionalLockDuration;
        if (newLockDuration > option.maxLockDuration) {
            revert InvalidStakeAmount();
        }

        // Validate against vesting schedule
        if (option.hasLinearVesting) {
            if (block.timestamp + newLockDuration < option.vestingStart + option.vestingDuration) {
                revert LockDurationTooShortForVesting();
            }
        }

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).beforeExtend(msg.sender, optionId, newLockDuration, userStake.data);
        }

        userStake.lockDuration = newLockDuration;
        userStake.lastExtensionTime = block.timestamp;

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).afterExtend(msg.sender, optionId, newLockDuration, userStake.data);
        }

        emit StakeExtended(optionId, msg.sender, newLockDuration);

        // Batch event
        emit StakingOperations(msg.sender, optionId, 0, newLockDuration, OPERATION_EXTEND);
    }

    function withdraw(uint256 optionId) external nonReentrantHooks whenNotEmergencyPaused {
        _withdraw(optionId);
    }

    function _withdraw(uint256 optionId) internal returns (uint256 amountWithdrawn, bool penaltyApplied) {
        Option storage option = options[optionId];
        Stake storage userStake = stakes[optionId][msg.sender];
        address hookAddr = option.hookContract;

        if (userStake.amount == 0) revert StakeNotFound();

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).beforeWithdraw(msg.sender, optionId, userStake.amount, userStake.data);
        }

        amountWithdrawn = userStake.amount;
        penaltyApplied = false;

        if (option.isLocked) {
            amountWithdrawn = _checkLockAndApplyPenalty(option, userStake, amountWithdrawn);
            penaltyApplied = amountWithdrawn != userStake.amount;
        }

        _transferTokens(option.token, msg.sender, amountWithdrawn);
        _resetUserStake(optionId, msg.sender);

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).afterWithdraw(msg.sender, optionId, amountWithdrawn, penaltyApplied, userStake.data);
        }

        emit Withdraw(optionId, msg.sender, amountWithdrawn, penaltyApplied);
        emit StakingOperations(msg.sender, optionId, amountWithdrawn, 0, OPERATION_WITHDRAW);

        return (amountWithdrawn, penaltyApplied);
    }

    /**
     * @notice Emergency withdraw function that can be used when contract is paused
     * @dev Only withdraws principal, no rewards/multipliers applied
     * @param optionId The ID of the staking option
     */
    function emergencyWithdraw(uint256 optionId) external nonReentrant {
        if (!emergencyPaused) revert EmergencyPauseNotActive();

        Option storage option = options[optionId];
        Stake storage userStake = stakes[optionId][msg.sender];

        if (userStake.amount == 0) revert StakeNotFound();

        uint256 amount = userStake.amount;
        _transferTokens(option.token, msg.sender, amount);
        _resetUserStake(optionId, msg.sender);

        emit EmergencyWithdraw(optionId, msg.sender, amount);
    }

    /**
     * @notice Withdraw a specific amount from the stake
     * @param optionId The ID of the staking option
     * @param amount The amount to withdraw
     */
    function withdrawPartial(uint256 optionId, uint256 amount) external nonReentrantHooks whenNotEmergencyPaused {
        Option storage option = options[optionId];
        Stake storage userStake = stakes[optionId][msg.sender];
        address hookAddr = option.hookContract;

        if (userStake.amount == 0) revert StakeNotFound();
        if (amount > userStake.amount) revert InsufficientBalance();

        uint256 withdrawableAmount = _getWithdrawableAmount(option, userStake);
        if (amount > withdrawableAmount) revert ExceedsWithdrawableAmount();

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).beforeWithdraw(msg.sender, optionId, amount, userStake.data);
        }

        uint256 amountToWithdraw = amount;
        bool penaltyApplied = false;

        if (option.isLocked) {
            amountToWithdraw = _checkLockAndApplyPenalty(option, userStake, amountToWithdraw);
            penaltyApplied = amountToWithdraw != amount;
        }

        userStake.amount -= amount;
        _transferTokens(option.token, msg.sender, amountToWithdraw);

        if (hookAddr != address(0)) {
            IStakingHooks(hookAddr).afterWithdraw(
                msg.sender, optionId, amountToWithdraw, penaltyApplied, userStake.data
            );
        }

        emit Withdraw(optionId, msg.sender, amountToWithdraw, penaltyApplied);
        emit StakingOperations(msg.sender, optionId, amountToWithdraw, 0, OPERATION_WITHDRAW);
    }

    function _getWithdrawableAmount(Option storage option, Stake storage userStake) internal view returns (uint256) {
        uint256 amountToWithdraw = userStake.amount;

        if (option.isLocked) {
            uint256 lockEndTime = userStake.creationTime + userStake.lockDuration;
            if (block.timestamp < lockEndTime) {
                return 0;
            }
        }

        if (option.hasLinearVesting) {
            uint256 vestedAmount = _getVestedAmount(option, userStake);
            amountToWithdraw = amountToWithdraw > vestedAmount ? vestedAmount : amountToWithdraw;
        }

        return amountToWithdraw;
    }

    function _checkLockAndApplyPenalty(Option storage option, Stake storage userStake, uint256 amountToWithdraw)
        internal
        returns (uint256)
    {
        uint256 lockEndTime = userStake.creationTime + userStake.lockDuration;
        if (block.timestamp < lockEndTime) revert WithdrawBeforeLockPeriod();

        if (option.hasEarlyExitPenalty) {
            uint256 penaltyAmount = (amountToWithdraw * option.penaltyPercentage) / 10000;
            amountToWithdraw -= penaltyAmount;

            if (option.penaltyRecipient != address(0)) {
                IERC20(option.token).safeTransfer(option.penaltyRecipient, penaltyAmount);
            } else {
                revert InsufficientBalanceForPenalty();
            }
        }

        return amountToWithdraw;
    }

    function _getVestedAmount(Option storage option, Stake storage userStake) internal view returns (uint256) {
        // Before cliff, nothing is vested
        if (block.timestamp < option.vestingStart + option.vestingCliff) {
            return 0;
        }

        // After vesting period, everything is vested
        if (block.timestamp >= option.vestingStart + option.vestingDuration) {
            return userStake.amount;
        }

        // During vesting period, calculate linear vesting
        uint256 timeElapsed = block.timestamp - option.vestingStart;
        uint256 vestedAmount = (userStake.amount * timeElapsed) / option.vestingDuration;

        return vestedAmount;
    }

    function _transferTokens(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function _resetUserStake(uint256 optionId, address staker) internal {
        delete stakes[optionId][staker];
    }

    // Validation Functions
    function _validateBasicParams(Option calldata option) internal pure {
        if (option.minStakeAmount == 0) revert MinimumStakeGreaterThanZero();
        if (option.maxStakeAmount != 0 && option.maxStakeAmount < option.minStakeAmount) {
            revert MaxStakeGreaterThanMinStake();
        }
        // Add base multiplier validation
        if (option.baseMultiplier < 10000) revert BaseMultiplierTooLow(); // 10000 = 100%
    }

    function _validateLockingParams(Option calldata option) internal pure {
        if (option.isLocked) {
            if (option.minLockDuration == 0) {
                revert LockedStakingMustHaveMinDuration();
            }
            if (option.maxLockDuration < option.minLockDuration) {
                revert MaxDurationGreaterThanMinDuration();
            }

            if (option.hasEarlyExitPenalty) {
                if (option.penaltyPercentage == 0 || option.penaltyPercentage > 10000) {
                    revert InvalidPenaltyPercentage();
                }
                if (option.penaltyRecipient == address(0)) {
                    revert PenaltyRecipientRequired();
                }
            }
        } else {
            if (option.minLockDuration != 0 || option.maxLockDuration != 0) {
                revert FlexibleStakingCannotHaveLockPeriods();
            }
            if (option.hasEarlyExitPenalty) {
                revert FlexibleStakingCannotHavePenalty();
            }
            if (option.penaltyPercentage != 0) {
                revert NoPenaltiesAllowedForFlexibleStaking();
            }
            if (option.penaltyRecipient != address(0)) {
                revert NoPenaltyRecipientForFlexibleStaking();
            }
        }
    }

    function _validateVestingParams(Option calldata option) internal view {
        if (option.hasLinearVesting) {
            // Require locking if vesting is enabled
            if (!option.isLocked) revert VestingRequiresLocking();

            if (option.vestingDuration == 0) revert VestingMustHaveDuration();
            if (option.vestingStart == 0) revert VestingMustHaveStartTime();
            // Ensure vesting start is within reasonable bounds (e.g., 7 days)
            if (option.vestingStart > block.timestamp + 7 days) {
                revert VestingStartTooFarInFuture();
            }
            if (option.vestingCliff > option.vestingDuration) {
                revert CliffMustBeLessThanOrEqualToVestingDuration();
            }
            if (option.vestingDuration > option.maxLockDuration) {
                revert VestingDurationExceedsLockDuration();
            }
        } else {
            if (option.vestingStart != 0 || option.vestingCliff != 0 || option.vestingDuration != 0) {
                revert NoVestingSettingsAllowed();
            }
        }
    }

    function _validateMultiplierParams(Option calldata option) internal pure {
        if (option.hasTimeBasedMultiplier) {
            if (option.multiplierIncreaseRate == 0) {
                revert MultiplierRateMustBeGreaterThanZero();
            }
        } else {
            if (option.multiplierIncreaseRate != 0) {
                revert NoMultiplierIncreaseRateIfDisabled();
            }
        }
    }

    /**
     * @notice Migrate stake from one option to another without unstaking
     * @param fromOptionId Source staking option ID
     * @param toOptionId Destination staking option ID
     */
    function migrateStake(uint256 fromOptionId, uint256 toOptionId) external nonReentrantHooks whenNotEmergencyPaused {
        _migrateStake(fromOptionId, toOptionId);
    }

    function _migrateStake(uint256 fromOptionId, uint256 toOptionId) internal returns (uint256 migratedAmount) {
        Option storage fromOption = options[fromOptionId];
        Option storage toOption = options[toOptionId];
        Stake storage fromStake = stakes[fromOptionId][msg.sender];

        if (fromStake.amount == 0) revert StakeNotFound();
        if (fromOption.isLocked) revert CannotMigrateLockedStake();
        if (toOption.paused) revert StakingPaused();

        if (
            fromStake.amount < toOption.minStakeAmount
                || (toOption.maxStakeAmount > 0 && fromStake.amount > toOption.maxStakeAmount)
        ) revert InvalidStakeAmount();

        if (fromOption.hookContract != address(0)) {
            IStakingHooks(fromOption.hookContract).beforeWithdraw(
                msg.sender, fromOptionId, fromStake.amount, fromStake.data
            );
        }

        if (toOption.hookContract != address(0)) {
            IStakingHooks(toOption.hookContract).beforeStake(msg.sender, toOptionId, fromStake.amount, 0, "");
        }

        migratedAmount = fromStake.amount;

        stakes[toOptionId][msg.sender] = Stake({
            amount: migratedAmount,
            lockDuration: 0,
            creationTime: block.timestamp,
            lastExtensionTime: block.timestamp,
            data: ""
        });

        delete stakes[fromOptionId][msg.sender];

        if (fromOption.hookContract != address(0)) {
            IStakingHooks(fromOption.hookContract).afterWithdraw(
                msg.sender, fromOptionId, migratedAmount, false, fromStake.data
            );
        }

        if (toOption.hookContract != address(0)) {
            IStakingHooks(toOption.hookContract).afterStake(msg.sender, toOptionId, migratedAmount, 0, "");
        }

        emit StakeMigrated(fromOptionId, toOptionId, msg.sender, migratedAmount);
        return migratedAmount;
    }

    /**
     * @notice Batch stake creation
     * @param optionIds Array of staking option IDs
     * @param amounts Array of amounts to stake
     * @param lockDurations Array of lock durations
     * @param datas Array of additional data for each stake
     */
    function batchStake(
        uint256[] calldata optionIds,
        uint256[] calldata amounts,
        uint256[] calldata lockDurations,
        bytes[] calldata datas
    ) external nonReentrantHooks whenNotEmergencyPaused {
        if (
            optionIds.length != amounts.length || optionIds.length != lockDurations.length
                || optionIds.length != datas.length
        ) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < optionIds.length; i++) {
            _stake(optionIds[i], amounts[i], lockDurations[i], datas[i]);
        }

        emit BatchStakeCreated(optionIds, msg.sender, amounts, lockDurations);
    }

    /**
     * @notice Batch stake extension
     * @param optionIds Array of staking option IDs
     * @param additionalLockDurations Array of additional lock durations
     */
    function batchExtendStake(uint256[] calldata optionIds, uint256[] calldata additionalLockDurations)
        external
        nonReentrantHooks
        whenNotEmergencyPaused
    {
        if (optionIds.length != additionalLockDurations.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < optionIds.length; i++) {
            _extendStake(optionIds[i], additionalLockDurations[i]);
        }

        emit BatchStakeExtended(optionIds, msg.sender, additionalLockDurations);
    }

    /**
     * @notice Batch withdraw
     * @param optionIds Array of staking option IDs
     */
    function batchWithdraw(uint256[] calldata optionIds) external nonReentrantHooks whenNotEmergencyPaused {
        uint256[] memory withdrawnAmounts = new uint256[](optionIds.length);
        bool[] memory penaltiesApplied = new bool[](optionIds.length);

        for (uint256 i = 0; i < optionIds.length; i++) {
            (withdrawnAmounts[i], penaltiesApplied[i]) = _withdraw(optionIds[i]);
        }

        emit BatchWithdraw(optionIds, msg.sender, withdrawnAmounts, penaltiesApplied);
    }

    /**
     * @notice Batch migrate stakes from one option to another without unstaking
     * @param fromOptionIds Array of source staking option IDs
     * @param toOptionIds Array of destination staking option IDs
     */
    function batchMigrateStake(uint256[] calldata fromOptionIds, uint256[] calldata toOptionIds)
        external
        nonReentrantHooks
        whenNotEmergencyPaused
    {
        if (fromOptionIds.length != toOptionIds.length) revert ArrayLengthMismatch();

        uint256[] memory migratedAmounts = new uint256[](fromOptionIds.length);

        for (uint256 i = 0; i < fromOptionIds.length; i++) {
            migratedAmounts[i] = _migrateStake(fromOptionIds[i], toOptionIds[i]);
        }

        emit BatchStakeMigrated(fromOptionIds, toOptionIds, msg.sender, migratedAmounts);
    }

    function getStake(uint256 optionId, address user) external view returns (Stake memory) {
        return stakes[optionId][user];
    }

    function getOption(uint256 optionId) external view returns (Option memory) {
        return options[optionId];
    }
}
