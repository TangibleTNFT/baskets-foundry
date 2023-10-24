// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../lib/forge-std/src/Script.sol";

// oz imports
//import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
//import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketsManager.sol";

import { VRFCoordinatorV2Mock } from "../test/utils/VRFCoordinatorV2Mock.sol";
import "../test/utils/MumbaiAddresses.sol";
import "../test/utils/Utility.sol";

// To run: forge script script/DeployBasketsToMumbai.s.sol:DeployBasketsToMumbai --rpc-url https://polygon-mumbai.infura.io/v3/6827bdf667064da4b2a0564cd45484d2 --broadcast --verify -vvvv

/**
 * @title DeployBasketsToMumbai
 * @author Chase Brown
 * @notice This script deploys a new instance of the baskets protocol (in full) to the Mumbai Testnet.
 */
contract DeployBasketsToMumbai is Script {

    // baskets
    Basket public basket;
    BasketManager public basketManager;

    // proxies
    ERC1967Proxy public basketManagerProxy;
    //TransparentUpgradeableProxy public basketVrfConsumerProxy;
    //ProxyAdmin public proxyAdmin;

    // wallets
    address immutable MUMBAI_DEPLOYER_ADDRESS = vm.envAddress("MUMBAI_DEPLOYER_ADDRESS");
    uint256 immutable MUMBAI_DEPLOYER_PRIVATE_KEY = vm.envUint("MUMBAI_DEPLOYER_PRIVATE_KEY");

    // vars
    /// @dev https://docs.chain.link/vrf/v2/subscription/supported-networks#polygon-matic-mumbai-testnet
    bytes32 public constant MUMBAI_VRF_KEY_HASH = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f; // 500 gwei

    uint64 internal subId;

    address deployerAddress;
    uint256 deployerPrivKey;

    function setUp() public {

        deployerAddress = MUMBAI_DEPLOYER_ADDRESS;
        deployerPrivKey = MUMBAI_DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        // 1. deploy basket
        basket = new Basket();

        // 2. Deploy basketManager
        basketManager = new BasketManager();

        // 3. Deploy proxy for basketManager & initialize
        basketManagerProxy = new ERC1967Proxy(
            address(basketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                Mumbai_FactoryV2
            )
        );

        // 4. deploy new basket -> NEED TOKENS TODO
        

        // log addresses
        console2.log("1. Basket Implementation: %s", address(basket));
        console2.log("2. BasketManager Implementation: %s", address(basketManager));
        console2.log("3. BasketManager Proxy: %s", address(basketManagerProxy));

        vm.stopBroadcast();
    }

    // Deployment 1:
    //   == Logs ==
    //   1. ProxyAdmin: 0x7c501F5f0A23Dc39Ac43d4927ff9f7887A01869B
    //   2. Mock Vrf Coordinator: 0x6a2EA328DE836222BFC7bEA20C348856d2770a99
    //   3. Basket Implementation: 0x541c058d0D7Ab8474Ea10fb090677FaD992256d9
    //   4. BasketManager Implementation: 0xBebe0cF3b3C881265803018fF211aBfc96FB3B61
    //   5. BasketManager Proxy: 0x95A3Af3e65A669792d5AbD2e058C4EcC34A98eBb
    //   6. BasketVrfConsumer Implementation: 0xAf960b9B057f59c68e55Ff9aC29966d9bf62b71B
    //   7. BasketVrfConsumer Proxy: 0x63284a454E9217c01c900428F1029dBBb784D9E3

    // Deployment 2:
    //     == Logs ==
    //   1. ProxyAdmin: 0x400f6195fd33E22DFB551F9e65AACf7BA4557040
    //   2. Mock Vrf Coordinator: 0x297670562a8BcfACBe5c30BBAC5ca7062ac7f652
    //   3. Basket Implementation: 0x7d262e3e7bb98e99595086fdE99c8AEDcc97d0fe
    //   4. BasketManager Implementation: 0x13bb0a0106ff48C422F6d91168f40FD66327549f
    //   5. BasketManager Proxy: 0x301AB99BbB929708bd18544D3D44d60BdE5ccF44
    //   6. BasketVrfConsumer Implementation: 0xb3221B24e57F7f6786FedE090D46a612f598Eff9
    //   7. BasketVrfConsumer Proxy: 0x366055CA18a4c21719BEC16a4dF5fBC43FFD4E64
}
