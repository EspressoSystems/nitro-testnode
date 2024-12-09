// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.9;

import "forge-std/Script.sol";
import "nitro-contracts/bridge/SequencerInbox.sol";
import "nitro-contracts/bridge/ISequencerInbox.sol";

/// @notice This contract deploys and initializes a sequencerInbox contract that orbit chains can migrate to that enables compatibility
/// with the espresso confirmation layer
/// @dev BATCH_POSTER_ADDRS should be a comma delimited list that includes addresses. This list will give batch posting affordances to those addresses
///        For chains using the Espresso TEE integration, this will be the address of your new batch poster, if you decide to change it.
contract DeployAndInitEspressoSequencerInboxTest is Script {
    function run() external {
        bool isMigrationTest = vm.envBool("IS_MIGRATION_TEST");
        // Grab addresses from env
        address reader4844Addr = vm.envAddress("READER_ADDRESS");

        // Grab any uints we need to initialize the contract from envAddress
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 maxDataSize = vm.envUint("MAX_DATA_SIZE");
        // Grab booleans we need from env
        bool isUsingFeeToken = vm.envBool("IS_USING_FEE_TOKEN");
        // Trick the Vm into seeing that this opcode exsists if this isn't the migration test
        if (!isMigrationTest){
           bytes memory code = vm.getDeployedCode("ArbSysMock.sol:ArbSysMock"); 
           vm.etch(0x0000000000000000000000000000000000000064, code);
        }
        // initialize interfaces needed
        IReader4844 reader = IReader4844(reader4844Addr);
        // Start broadcast to deploy the SequencerInbox
        vm.startBroadcast(deployerPrivateKey);
        SequencerInbox sequencerInbox = new SequencerInbox(maxDataSize, reader, isUsingFeeToken);
        
        // Setting batch posters and batch poster manager
        vm.stopBroadcast();
    }
}
