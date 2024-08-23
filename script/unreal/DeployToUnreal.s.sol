// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// tangible imports
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";
import { IBasket } from "../../src/interfaces/IBasket.sol";
import { BasketManager } from "../../src/BasketManager.sol";
import { CurrencyCalculator } from "../../src/CurrencyCalculator.sol";
import { BasketsVrfConsumer } from "../../src/BasketsVrfConsumer.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";

/** 
    @dev To run: 
    forge script script/unreal/DeployToUnreal.s.sol:DeployToUnreal --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api
*/

/**
 * @title DeployToUnreal
 * @author Chase Brown
 * @notice This script deploys a new instance of the baskets protocol (in full) to the Unreal Testnet.
 */
contract DeployToUnreal is Script {

    // ~ Script Configure ~

    // baskets
    Basket public basket;
    BasketManager public basketManager;
    CurrencyCalculator public currencyCalculator;
    BasketsVrfConsumer public basketVrfConsumer;

    // marketplace contracts
    address public UNREAL_FACTORY = 0x61d595f7e7E9e08340c7B044499F5A25149b8Fca;

    // wallets
    address immutable DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    address public constant GELATO_VRF_OPERATOR = address(0); // TODO If necessary. Testnet has fulfillRandomnessTestnet which is permissionless

    uint256 public constant UNREAL_CHAIN_ID = 18233;

    address deployerAddress;
    uint256 deployerPrivKey;

    address public factoryOwner = 0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7;

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {

        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // 1. deploy basket
        basket = new Basket();

        // 2. Deploy CurrencyCalculator
        currencyCalculator = new CurrencyCalculator();

        // 3. Deploy proxy for CurrencyCalculator -> initialize
        ERC1967Proxy currencyCalculatorProxy = new ERC1967Proxy(
            address(currencyCalculator),
            abi.encodeWithSelector(CurrencyCalculator.initialize.selector,
                UNREAL_FACTORY,
                24 hours,
                31 days
            )
        );
        currencyCalculator = CurrencyCalculator(address(currencyCalculatorProxy));

        // 4. Deploy basketManager
        basketManager = new BasketManager();

        // 5. Deploy proxy for basketManager & initialize
        ERC1967Proxy basketManagerProxy = new ERC1967Proxy(
            address(basketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                UNREAL_FACTORY,
                Unreal_USTB,
                true,
                address(currencyCalculator)
            )
        );
        basketManager = BasketManager(address(basketManagerProxy));

        // 6. Deploy BasketsVrfConsumer
        basketVrfConsumer = new BasketsVrfConsumer();

        // 7. Initialize BasketsVrfConsumer with proxy
        ERC1967Proxy basketVrfConsumerProxy = new ERC1967Proxy(
            address(basketVrfConsumer),
            abi.encodeWithSelector(BasketsVrfConsumer.initialize.selector,
                UNREAL_FACTORY,
                UNREAL_CHAIN_ID /// NOTE TESTNET CHAINID ONLY
            )
        );
        basketVrfConsumer = BasketsVrfConsumer(address(basketVrfConsumerProxy));

        // 8. TODO: Create and set Gelato Operator via BasketsVrfConsumer::updateOperator

        // 9. TODO: set basketsVrfConsumer via BasketManager::setBasketsVrfConsumer

        // 10. TODO: set revenueShare via BasketManager::setRevenueShare -> SET REVENUE DISTRIBUTOR

        // 11. TODO: Ensure the new basket manager is added on factory and is whitelister on notification dispatcher

        // 12. TODO: Call setRebaseController on BasketManager to set controller.

        // 13. TODO: If not already deployed, deploy basketRebaseManagerDeployer.

        // 14. TODO: Make sure basket contract is opted out of USTB reabse
    

        // log addresses
        console2.log("1. BasketManager =", address(basketManager));
        console2.log("2. BasketVrfConsumer =", address(basketVrfConsumer));
        console2.log("3. CurrencyCalculator =", address(currencyCalculator));
    
        vm.stopBroadcast();
    }
}