// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/FlexStake.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {console} from "forge-std/console.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        FlexStake implementation = new FlexStake();
        console.log("Implementation contract deployed at:", address(implementation));

        // Deploy proxy admin
        ProxyAdmin proxyAdmin = new ProxyAdmin(deployerAddress);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // Create initialization data
        bytes memory initData = abi.encodeWithSelector(FlexStake.initialize.selector, deployerAddress);
        console.log("Initialization data prepared for owner:", deployerAddress);

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        console.log("Proxy contract deployed at:", address(proxy));
        console.log("To interact with the contract, use this address:", address(proxy));

        vm.stopBroadcast();

        // Log verification information
        console.log("\nVerification information:");
        console.log("Implementation:", address(implementation));
        console.log("Proxy:", address(proxy));
        console.log("ProxyAdmin:", address(proxyAdmin));
    }
}
