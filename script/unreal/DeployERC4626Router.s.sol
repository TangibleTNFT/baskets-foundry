// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "../../lib/forge-std/src/Script.sol";

// local contracts
import { ERC4626FeeOnTransferRouter } from "../../src/wrapped/ERC4626FeeOnTransferRouter.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";

/** 
    @dev To run: 
    forge script script/unreal/DeployERC4626Router.s.sol:DeployERC4626Router --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api
*/

/**
 * @title DeployERC4626Router
 * @author Chase Brown
 * @notice This script deploys a new instance of a wrapped baskets vault token to the Unreal Testnet.
 */
contract DeployERC4626Router is Script {

    // ~ Script Configure ~

    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {

        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        ERC4626FeeOnTransferRouter router = new ERC4626FeeOnTransferRouter();
        console.log("router address:", address(router));
    
        vm.stopBroadcast();
    }
}