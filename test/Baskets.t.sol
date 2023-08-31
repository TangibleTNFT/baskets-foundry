// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

// local contracts
import { Basket } from "../src/Baskets.sol";
import { BasketDeployer } from "../src/BasketsDeployer.sol";

// tangible contract imports
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { FactoryProvider } from "@tangible/FactoryProvider.sol";
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { TangiblePriceManagerV2 } from "@tangible/TangiblePriceManagerV2.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { CurrencyFeedV2 } from "@tangible/helpers/CurrencyFeedV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { TNFTMarketplaceV2 } from "@tangible/MarketplaceV2.sol";

// tangible interface imports
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IRentManager } from "@tangible/interfaces/IRentManager.sol";

// https://docs.chain.link/data-feeds/price-feeds/addresses/?network=polygon#Polygon%20Mainnet
// Polygon GBP / USD Price Feed: 0x099a2540848573e94fb1Ca0Fa420b00acbBc845a
// polygon USDC / USD Price Feed: 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7

// chainlinkRWAOracle -> 0x731209585143011778C56BDfaAf87d341adE7C07

interface ITangibleOracle {
    function createItem(
        uint256 fingerprint,
        uint256 weSellAt,
        uint256 lockedAmount,
        uint256 weSellAtStock,
        uint16 currency,
        uint16 location
    ) external;
}

contract BasketsTest is Test {
    Basket public basket;
    BasketDeployer public basketDeployer;

    FactoryProvider public factoryProvider;
    FactoryV2 public factory;
    TangibleNFTV2 public tnft;
    CurrencyFeedV2 public currencyFeed;
    TNFTMetadata public metadata;
    TangiblePriceManagerV2 public priceManager;
    RealtyOracleTangibleV2 public realEstateOracle;
    TNFTMarketplaceV2 public marketplace;

    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    address public constant POLYGON_CHAINLINK_GBPUSD_PRICE_FEED = 0x099a2540848573e94fb1Ca0Fa420b00acbBc845a;
    address public constant POLYGON_CHAINLINK_USDCUSD_PRICE_FEED = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;

    address public constant TANGIBLE_ORACLE = 0x731209585143011778C56BDfaAf87d341adE7C07;
    address public constant TANGIBLE_ORACLE_OWNER = 0x7179B719EEd8c2C60B498d2A2d04f868fb655F22;

    string public constant BASE_URI = "https://example.gateway.com/ipfs/CID";

    uint256 constant public FINGERPRINT = 111;
    uint256 constant public TNFTTYPE = 1;
    uint256[] public featuresArray;

    // Actors
    address public constant JOE = address(bytes20(bytes("Joe")));
    address public constant ADMIN = address(bytes20(bytes("Admin")));
    address public constant TANGIBLE_LABS = address(bytes20(bytes("Tangible Labs Multisig")));

    function setUp() public {

        // Deploy Factory
        factory = new FactoryV2(
            USDC,
            TANGIBLE_LABS
        );

        // Deploy Factory Provider
        factoryProvider = new FactoryProvider();
        factoryProvider.initialize(address(factory));

        // Deploy Marketplace
        marketplace = new TNFTMarketplaceV2(
            address(factoryProvider)
        );

        // Deploy Currency Feed
        currencyFeed = new CurrencyFeedV2(
            address(factoryProvider)
        );

        // Deploy Price Manager
        priceManager = new TangiblePriceManagerV2(
            address(factoryProvider)
        );

        // Deploy Real Estate Oracle
        realEstateOracle = new RealtyOracleTangibleV2(
            address(factoryProvider),
            address(currencyFeed),
            TANGIBLE_ORACLE
        );

        // Deploy TNFT Metadata
        metadata = new TNFTMetadata(
            address(factoryProvider)
        );

        tnft = new TangibleNFTV2(
            address(factoryProvider),
            "TangibleREstate",
            "RLTY", 
            BASE_URI,
            false,
            false,
            false,
            TNFTTYPE
        );

        // Deploy basket
        basket = new Basket(
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            1, // tnftType
            address(currencyFeed)
        );


        // ~ configuration ~

        factory.setContract(FactoryV2.FACT_ADDRESSES.LABS, TANGIBLE_LABS);
        factory.setContract(FactoryV2.FACT_ADDRESSES.PRICE_MANAGER, address(priceManager));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_META, address(metadata));
        factory.setContract(FactoryV2.FACT_ADDRESSES.MARKETPLACE, address(marketplace));

        factory.setCategory(
            "TangibleREstate",
            ITangibleNFT(address(tnft)),
            IRentManager(address(888)), // TODO: Revisit -> rentManager
            address(realEstateOracle),
            address(this)
        );

        tnft.addFingerprints(_asSingletonArrayUint(FINGERPRINT));

        vm.prank(TANGIBLE_ORACLE_OWNER);
        ITangibleOracle(TANGIBLE_ORACLE).createItem(
            FINGERPRINT, // fingerprint
            50000000,    // weSellAt
            0,           // lockedAmount
            1,           // stock
            uint16(826),         // currency -> GBP ISO NUMERIC CODE TODO: VERIFY
            uint16(136)          // country -> Cayman Islands, UK ISO NUMERIC CODE TODO: VERIFY
        );

        IVoucher.MintVoucher memory voucher = IVoucher.MintVoucher(
            ITangibleNFT(address(tnft)),   // token
            1,                             // mintCount
            1,                             // price     // TODO: Verify
            TANGIBLE_LABS,                 // vendor
            JOE,                           // buyer
            FINGERPRINT,                   // fingerprint
            true                           // sendToVender
        );

        vm.prank(TANGIBLE_LABS);
        factory.mint(voucher);
        
    }


    // ~ Utility ~ 

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayUint(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }


    // ~ Initial State Test ~

    /// @notice Initial state test.
    function test_basket_init_state() public {}


    // ~ Unit Tests ~

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_depositTNFT() public {
        assertTrue(true);
    }

}
