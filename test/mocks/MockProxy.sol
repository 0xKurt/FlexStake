// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/Proxy.sol";

contract MockProxy is Proxy {
    address private _impl; // Renamed to avoid shadowing

    constructor(address implementation_, bytes memory _data) {
        _impl = implementation_;
        (bool success,) = implementation_.delegatecall(_data);
        require(success, "Initialization failed");
    }

    function _implementation() internal view override returns (address) {
        return _impl;
    }

    receive() external payable {} // Add receive function
}
