// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./IStakingHooks.sol";

abstract contract BaseStakingHooks is IStakingHooks, ERC165 {
    /// @dev ERC165 interface ID for IStakingHooks interface
    bytes4 public constant ISTAKING_HOOKS_INTERFACE_ID = type(IStakingHooks).interfaceId;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == ISTAKING_HOOKS_INTERFACE_ID ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Hook that is called before staking.
     */
    function beforeStake(
        address user,
        uint256 optionId,
        uint256 amount,
        uint256 duration,
        bytes calldata data
    ) external virtual override {
        _beforeStake(user, optionId, amount, duration, data);
    }

    /**
     * @dev Hook that is called after staking.
     */
    function afterStake(
        address user,
        uint256 optionId,
        uint256 amount,
        uint256 duration,
        bytes calldata data
    ) external virtual override {
        _afterStake(user, optionId, amount, duration, data);
    }

    /**
     * @dev Hook that is called before unstaking.
     */
    function beforeUnstake(
        address user,
        uint256 stakeId,
        bytes calldata data
    ) external virtual override {
        _beforeUnstake(user, stakeId, data);
    }

    /**
     * @dev Hook that is called after unstaking.
     */
    function afterUnstake(
        address user,
        uint256 stakeId,
        bytes calldata data
    ) external virtual override {
        _afterUnstake(user, stakeId, data);
    }

    /**
     * @dev Internal implementation of beforeStake hook.
     */
    function _beforeStake(
        address user,
        uint256 optionId,
        uint256 amount,
        uint256 duration,
        bytes calldata data
    ) internal virtual {}

    /**
     * @dev Internal implementation of afterStake hook.
     */
    function _afterStake(
        address user,
        uint256 optionId,
        uint256 amount,
        uint256 duration,
        bytes calldata data
    ) internal virtual {}

    /**
     * @dev Internal implementation of beforeUnstake hook.
     */
    function _beforeUnstake(
        address user,
        uint256 stakeId,
        bytes calldata data
    ) internal virtual {}

    /**
     * @dev Internal implementation of afterUnstake hook.
     */
    function _afterUnstake(
        address user,
        uint256 stakeId,
        bytes calldata data
    ) internal virtual {}
} 