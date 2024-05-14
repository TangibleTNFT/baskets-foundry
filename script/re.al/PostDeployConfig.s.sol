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

// tangible contract
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { RWAPriceNotificationDispatcher } from "@tangible/notifications/RWAPriceNotificationDispatcher.sol";

// helper contracts
import "../../test/utils/Re.alAddresses.sol";
import "../../test/utils/Utility.sol";

/** 
    @dev To run: 
    forge script script/re.al/DeployAll.s.sol:DeployAll --broadcast --legacy \
    --gas-estimate-multiplier 600 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 111188 --watch \
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://explorer.re.al//api
*/

/**
 * @title DeployAll
 * @author Chase Brown
 * @notice This script deploys a new instance of the baskets protocol (in full) to the Unreal Testnet.
 */
contract DeployAll is Script {

    // ~ Script Configure ~

    // baskets
    BasketManager constant public basketManager = BasketManager(0x5e581ce0472bF528E7F5FCB96138d7759AC2ac3f);
    CurrencyCalculator constant public currencyCalculator = CurrencyCalculator(0xE5bf6fb71DCBBc298C602d92Ce0AE7DF2456266f);
    BasketsVrfConsumer constant public basketVrfConsumer = BasketsVrfConsumer(0x68179D8f2dbd5969F421DfC5f92C40ecDD530c41);

    // marketplace contracts
    FactoryV2 constant public factoryV2 = FactoryV2(Real_FactoryV2);
    RWAPriceNotificationDispatcher constant public notificationDispatcher = RWAPriceNotificationDispatcher(Real_RWAPriceNotificationDispatcher);

    address constant public gelatoOperator = 0xd47898C61fCd69AB8257a369416218Df6EcA5C7c;

    // wallets
    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
    }

    function run() public {

        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // 1. Create and set Gelato Operator via BasketsVrfConsumer::updateOperator
        basketVrfConsumer.updateOperator(gelatoOperator);

        // 2. set basketsVrfConsumer via BasketManager::setBasketsVrfConsumer
        basketManager.setBasketsVrfConsumer(address(basketVrfConsumer));

        // 3. TODO: set revenueShare via BasketManager::setRevenueShare -> SET REVENUE DISTRIBUTOR (Not deployed yet)

        // 4. Ensure the new basket manager is added on factory and is whitelister on notification dispatcher
        factoryV2.setContract(FactoryV2.FACT_ADDRESSES.BASKETS_MANAGER, address(basketManager));
        notificationDispatcher.addWhitelister(address(basketManager));

        // 5. Call setRebaseController on BasketManager to set controller.
        basketManager.setRebaseController(Real_RebaseController);
    
        vm.stopBroadcast();
    }
}