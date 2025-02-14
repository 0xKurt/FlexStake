# FlexStake

FlexStake is a flexible staking contract that supports multiple staking options with various features including locking, vesting, penalties, and hooks.

## Features Overview

The contract allows creation of customizable staking options with the following features:

- Flexible or locked staking periods
- Linear vesting schedules
- Early exit penalties
- Time-based multipliers
- Custom data attachments
- Hook contracts for extended functionality
- Emergency pause mechanism
- Auto-renewal options
- Minimum and maximum stake amounts
- User-defined lock periods

## Staking Types

### 1. Flexible Staking
- No lock period required
- Stake and unstake at any time
- No penalties for withdrawal
- Supports custom data and hooks
- Optional time-based multipliers

### 2. Fixed-Term Staking
- Predefined lock periods
- Early withdrawal restrictions
- Optional features:
  - Early exit penalties (1-100%)
  - Linear vesting schedules
  - Time-based multipliers
  - Auto-renewal
  - Hook contracts

### 3. Amount Configurations
- Optional amount restrictions:
  - No restrictions (default)
  - Single fixed amount
  - Min/max range

## Time-Based Multiplier System

### Overview
The time-based multiplier provides a dynamic value that increases based on stake duration:
```
Total Value = Staked Amount * (1 + (timeStaked * multiplierIncreaseRate / 10000))
```

### Examples

1. **1% Daily Increase**
```
multiplierIncreaseRate = 100
After 10 days: 110% of staked amount
After 30 days: 130% of staked amount
After 365 days: 465% of staked amount
```

2. **0.1% Daily Increase**
```
multiplierIncreaseRate = 10
After 10 days: 101% of staked amount
After 30 days: 103% of staked amount
After 365 days: 136.5% of staked amount
```

## Validation Rules

1. **Amount Configuration**
   - If using single amount: minAmount = maxAmount
   - If using range: maxAmount > minAmount
   - If no restrictions: amounts = 0

2. **Locked Staking**
   - Minimum lock duration must be > 0
   - Maximum lock duration must be > minimum
   - Penalty percentage must be between 1-10000 (0.01%-100%)
   - Penalty recipient required if penalty enabled
   - Vesting requires locking to be enabled

3. **Vesting**
   - Duration must be > 0
   - Start time must be within 7 days
   - Cliff period must be ≤ vesting duration
   - Only available with locked staking

4. **Time-Based Multiplier**
   - Increase rate must be > 0 if enabled
   - Available for both flexible and locked staking

5. **Data Requirements**
   - If data is required, stake must include non-empty data
   - If data not required, stake must not include data

## Creating a Staking Option

```solidity
Option memory option = Option({
    id: 0, // Will be set by contract
    isLocked: true,
    minLockDuration: 7 days,
    maxLockDuration: 365 days,
    hasEarlyExitPenalty: true,
    penaltyPercentage: 1000, // 10%
    penaltyRecipient: penaltyAddress,
    minStakeAmount: 100,
    maxStakeAmount: 1000,
    hasLinearVesting: true,
    vestingStart: block.timestamp,
    vestingCliff: 7 days,
    vestingDuration: 30 days,
    hasTimeBasedMultiplier: true,
    multiplierIncreaseRate: 100, // 1% daily increase
    token: tokenAddress,
    requiresData: false,
    hookContract: address(0)
});

uint256 optionId = flexStake.createOption(option);
```

## Core Functions

### Staking
```solidity
function stake(uint256 optionId, uint256 amount, uint256 lockDuration, bytes calldata data) external
```

### Extending Lock Duration
```solidity
function extendStake(uint256 optionId, uint256 additionalLockDuration) external
```

### Withdrawing
```solidity
function withdraw(uint256 optionId) external
function withdrawPartial(uint256 optionId, uint256 amount) external
```

### Checking Values
```solidity
function getStakedValue(uint256 optionId, address user) external view returns (uint256)
function getStake(uint256 optionId, address user) external view returns (Stake memory)
```

## Emergency Features

1. **Emergency Pause**
   - Pauses all contract operations
   - Only owner can activate/deactivate
   - Emergency withdrawals still possible

2. **Option-specific Pause**
   - Pauses new stakes for specific option
   - Existing stakes follow normal rules
   - Only owner can activate/deactivate

3. **Pause and Release**
   - Pauses new stakes for specific option
   - Releases all existing stakes from lock periods
   - Disables penalties for withdrawals
   - Cannot be reversed
   - Only owner can activate

## Hook System
The contract supports hook contracts implementing IStakingHooks interface for:
- Pre and post stake operations
- Pre and post withdraw operations
- Pre and post extension operations
- Custom validation and logic
- External reward systems

## License
MIT
