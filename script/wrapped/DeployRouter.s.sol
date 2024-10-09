// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Script.sol";
import {DeployUtility} from "../DeployUtility.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { WrappedBasketToken } from "../../src/wrapped/WrappedBasketToken.sol";
import { ERC4626FeeOnTransferRouter } from "../../src/wrapped/ERC4626FeeOnTransferRouter.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";
import "../utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/wrapped/DeployRouter.s.sol:DeployRouter --broadcast --legacy \
    --gas-estimate-multiplier 500 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch \
    src/wrapped/ERC4626FeeOnTransferRouter.sol:ERC4626FeeOnTransferRouter \
    --verifier blockscout --verifier-url https://explorer.re.al//api
*/

/**
 * @title DeployRouter
 * @author Chase Brown
 * @notice This script deploys a new ERC4626FeeOnTransferRouter
 */
contract DeployRouter is DeployUtility {

    // ~ Script Configure ~

    address immutable public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {
        _setup("router.mainnet.deployment");
    }

    function run() public {

        vm.createSelectFork(vm.envString("REAL_RPC_URL"));
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        address vaultRouterAddress = address(new ERC4626FeeOnTransferRouter());

        // save vaultRouterAddress addresses to appropriate JSON
        _saveDeploymentAddress("real", "ERC4626FeeOnTransferRouter", vaultRouterAddress);
        vm.stopBroadcast();
    }
}