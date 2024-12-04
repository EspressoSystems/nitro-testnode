// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Script.sol";
import "nitro-contracts/mocks/EspressoTEEVerifier.sol";

contract DeployMockVerifier is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        EspressoTEEVerifierMock mockVerifier = new EspressoTEEVerifierMock();
        vm.stopBroadcast();
    }
}
