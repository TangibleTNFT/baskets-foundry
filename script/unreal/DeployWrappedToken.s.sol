// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";
import { WrappedBasketToken } from "../../src/wrapped/WrappedBasketToken.sol";
import { IBasket } from "../../src/interfaces/IBasket.sol";
import { BasketManager } from "../../src/BasketManager.sol";
import { CurrencyCalculator } from "../../src/CurrencyCalculator.sol";
import { BasketsVrfConsumer } from "../../src/BasketsVrfConsumer.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";

/** 
    @dev To run: 
    forge script script/unreal/DeployWrappedToken.s.sol:DeployWrappedToken --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api
*/

/**
 * @title DeployWrappedToken
 * @author Chase Brown
 * @notice This script deploys a new instance of a wrapped baskets vault token to the Unreal Testnet.
 */
contract DeployWrappedToken is Script {

    // ~ Script Configure ~

    address basket = 0x8bBE2FE226a5d1432ae242B63EFC79c1787D0cF2;
    address lzEndpoint = 0x83c73Da98cf733B03315aFa8758834b36a195b87;

    address immutable DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {

        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy WrappedBasketToken
        WrappedBasketToken wUKRE = new WrappedBasketToken(
            lzEndpoint, // TODO: LZ Endpoint for re.al
            basket // UKRE
        );

        // Deploy proxy for WrappedBasketToken -> initialize
        new ERC1967Proxy(
            address(wUKRE),
            abi.encodeWithSelector(WrappedBasketToken.initialize.selector,
                DEPLOYER_ADDRESS,
                "Wrapped UKRE",
                "wUKRE"
            )
        );
    
        vm.stopBroadcast();
    }
}