// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../lib/forge-std/src/StdInvariant.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// oz imports
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// tangible contract
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { RentManagerDeployer } from "@tangible/RentManagerDeployer.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { TNFTMarketplaceV2 } from "@tangible/MarketplaceV2.sol";
import { TangiblePriceManagerV2 } from "@tangible/TangiblePriceManagerV2.sol";
import { CurrencyFeedV2 } from "@tangible/helpers/CurrencyFeedV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { RentManager } from "@tangible/RentManager.sol";
import { RWAPriceNotificationDispatcher } from "@tangible/notifications/RWAPriceNotificationDispatcher.sol";
import { MockMatrixOracle } from "@tangible/tests/mocks/MockMatrixOracle.sol";

// tangible interface imports
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { CurrencyCalculator } from "../src/CurrencyCalculator.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketManager.sol";
import { BasketsVrfConsumer } from "../src/BasketsVrfConsumer.sol";
import { IGetNotificationDispatcher } from "../src/interfaces/IGetNotificationDispatcher.sol";
import { IUSTB } from "../src/interfaces/IUSTB.sol";

// local helper contracts
import "./utils/UnrealAddresses.sol";
import "./utils/Utility.sol";


/**
 * @title BasketsRentUpdateTest
 * @author Chase Brown
 * @notice This test file contains integration tests simulating the update in rent token that the production UKRE
 * is anticipated to undergo.
 */
contract BasketsRentUpdateTest is Utility {

    // ~ Contracts ~

    // baskets
    Basket public constant UKRE = Basket(0x835d3E1C0aA079C6164AAd21DCb23E60eb71AF48);
    BasketManager public constant basketManager = BasketManager(0x5e581ce0472bF528E7F5FCB96138d7759AC2ac3f);

    //CurrencyCalculator public currencyCalculator;
    //BasketsVrfConsumer public basketVrfConsumer;

    // tangible unreal contracts
    FactoryV2 public constant factoryV2 = FactoryV2(0x6DD9abb56CeCbC6FCB27a716bBECd1eFDfE09f5F);
    RentManagerDeployer public constant rentManagerDeployer = RentManagerDeployer(0x0cC6afE54AFa1AeF0Ec94CC8471859812C54D8De);
    TangibleNFTV2 public constant realEstateTnft = TangibleNFTV2(0x03634A8Aea4Ca702c0Af7b1480c5015e5BbF3cb9);
    // RealtyOracleTangibleV2 public realEstateOracle = RealtyOracleTangibleV2(Unreal_RealtyOracleTangibleV2);
    // MockMatrixOracle public chainlinkRWAOracle = MockMatrixOracle(Unreal_MockMatrix);
    // TNFTMarketplaceV2 public marketplace = TNFTMarketplaceV2(Unreal_Marketplace);
    // TangiblePriceManagerV2 public priceManager = TangiblePriceManagerV2(Unreal_PriceManager);
    // CurrencyFeedV2 public currencyFeed = CurrencyFeedV2(Unreal_CurrencyFeedV2);
    // TNFTMetadata public metadata = TNFTMetadata(Unreal_TNFTMetadata);
    // RentManager public rentManager = RentManager(Unreal_RentManagerTnft);
    // RWAPriceNotificationDispatcher public notificationDispatcher = RWAPriceNotificationDispatcher(Unreal_RWAPriceNotificationDispatcher);

    // ~ Actors and Variables ~

    address public FACTORY_OWNER;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    //address public TANGIBLE_LABS; // NOTE: category owner

    address public constant MULTISIG = 0x5111e9bCb01de69aDd95FD31B0f05df51dF946F4;
    address public constant USTB = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    address public constant USDC = 0xc518A88c67CECA8B3f24c4562CB71deeB2AF86B7;

    /// @notice Config function for test cases.
    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL, 766184); // fork - re.al block 766184 @ Sep 30th 2024 10:49:10am (-07:00 UTC)

        FACTORY_OWNER = IOwnable(address(factoryV2)).owner();

        // new category owner
        //TANGIBLE_LABS = factoryV2.categoryOwner(ITangibleNFT(address(realEstateTnft)));

        vm.prank(FACTORY_OWNER);
        UKRE.updatePrimaryRentToken(USDC, false);

        _createLabels();

        _updateRentManager();
    }


    // -------
    // Utility
    // -------

    /// @notice Creates labels for addresses. Makes traces easier to read.
    function _createLabels() internal override {
        vm.label(address(this), "TEST_FILE");
        //vm.label(TANGIBLE_LABS, "TANGIBLE_LABS");
        super._createLabels();
    }

    function _overwriteRentManagerOnFactory(address newRentManager) internal {
        assertNotEq(address(factoryV2.rentManager(realEstateTnft)), newRentManager);

        bytes32 USTBStorageLocation = 0x8a0c9d8ec1d9f8b365393c36404b40a33f47675e34246a2e186fbefd5ecd3b00;
        uint256 mapSlot = 18;
        bytes32 slot = keccak256(abi.encode(address(realEstateTnft), mapSlot));
        vm.store(address(factoryV2), slot, bytes32(abi.encodePacked(newRentManager)));

        assertEq(address(factoryV2.rentManager(realEstateTnft)), newRentManager);
    }

    function _updateRentManager() internal returns (address) {
        // deploy new rentManager
        vm.prank(address(factoryV2));
        address newRentManager = address(rentManagerDeployer.deployRentManager(address(realEstateTnft)));
        // update address on factory
        _overwriteRentManagerOnFactory(newRentManager);
    }


    // ----------
    // Unit Tests
    // ----------

    function test_rentUpdate_getRentBal() public {}

    function test_rentUpdate_getTotalValueOfBasket() public {}

    function test_rentUpdate_decimalsDiff() public {}

    function test_rentUpdate_withdrawRent() public {}

    function test_rentUpdate_rebase() public {}
    
    function test_rentUpdate_deposit() public {}
}