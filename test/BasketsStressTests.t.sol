// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../lib/forge-std/src/StdInvariant.sol";

// oz imports
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketsManager.sol";
import { BasketsVrfConsumer } from "../src/BasketsVrfConsumer.sol";

import { VRFCoordinatorV2Mock } from "./utils/VRFCoordinatorV2Mock.sol";
import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";

// tangible contract imports
import { FactoryProvider } from "@tangible/FactoryProvider.sol";
import { FactoryV2 } from "@tangible/FactoryV2.sol";

// tangible interface imports
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { IChainlinkRWAOracle } from "@tangible/interfaces/IChainlinkRWAOracle.sol";
import { IMarketplace } from "@tangible/interfaces/IMarketplace.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";
import { IRentManager } from "@tangible/interfaces/IRentManager.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/// @notice This test file 
contract MumbaiBasketsTest is Utility {

    Basket public basket;
    BasketManager public basketManager;
    BasketsVrfConsumer public basketVrfConsumer;

    VRFCoordinatorV2Mock public vrfCoordinatorMock;

    //contracts
    IFactory public factoryV2 = IFactory(Mumbai_FactoryV2);
    ITangibleNFT public realEstateTnft = ITangibleNFT(Mumbai_TangibleREstateTnft);
    IPriceOracle public realEstateOracle = IPriceOracle(Mumbai_RealtyOracleTangibleV2);
    //IChainlinkRWAOracle public chainlinkRWAOracle = IChainlinkRWAOracle(Mumbai_ChainlinkOracle);
    IChainlinkRWAOracle public chainlinkRWAOracle = IChainlinkRWAOracle(Mumbai_MockMatrix);
    IMarketplace public marketplace = IMarketplace(Mumbai_Marketplace);
    IFactoryProvider public factoryProvider = IFactoryProvider(Mumbai_FactoryProvider);
    ITangiblePriceManager public priceManager = ITangiblePriceManager(Mumbai_PriceManager);
    ICurrencyFeedV2 public currencyFeed = ICurrencyFeedV2(Mumbai_CurrencyFeedV2);
    ITNFTMetadata public metadata = ITNFTMetadata(Mumbai_TNFTMetadata);
    IRentManager public rentManager = IRentManager(Mumbai_RentManagerTnft);

    mapping(address => uint256[]) internal tokenIdMap;

    // ~ Actors ~

    address public factoryOwner;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public constant TANGIBLE_LABS = 0x23bfB039Fe7fE0764b830960a9d31697D154F2E4; // NOTE: category owner

    address public rentManagerDepositor = 0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7;

    // State variables for VRF.
    uint64 internal subId;
    
    event log_named_bool(string key, bool val);


    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        factoryOwner = IOwnable(address(factoryV2)).contractOwner();

        // vrf config
        vrfCoordinatorMock = new VRFCoordinatorV2Mock(100000, 100000);
        subId = vrfCoordinatorMock.createSubscription();
        vrfCoordinatorMock.fundSubscription(subId, 100 ether);

        // basket stuff
        basket = new Basket();
        basketManager = new BasketManager(
            address(basket),
            address(factoryProvider)
        );

        // updateDepositor for rent manager
        vm.prank(TANGIBLE_LABS);
        rentManager.updateDepositor(TANGIBLE_LABS);

        // set basketManager
        vm.prank(factoryOwner);
        IFactoryExt(address(factoryV2)).setContract(IFactoryExt.FACT_ADDRESSES.BASKETS_MANAGER, address(basketManager));

        // set currencyFeed
        vm.prank(factoryOwner);
        IFactoryExt(address(factoryV2)).setContract(IFactoryExt.FACT_ADDRESSES.CURRENCY_FEED, address(currencyFeed));

        // Deploy Basket
        uint256[] memory features = new uint256[](0);
        vm.prank(address(basket)); // NOTE: Should be proxy
        basket.initialize( 
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            address(this)
        );

        // Deploy BasketsVrfConsumer
        basketVrfConsumer = new BasketsVrfConsumer();

        // Initialize BasketsVrfConsumer
        vm.prank(PROXY);
        basketVrfConsumer.initialize(
            address(factoryProvider),
            subId,
            address(vrfCoordinatorMock),
            MUMBAI_VRF_KEY_HASH
        );

        // add basket to basketManager
        vm.prank(factoryOwner);
        basketManager.addBasket(address(basket));

        vm.prank(factoryOwner);
        basketManager.setBasketsVrfConsumer(address(basketVrfConsumer));

        vrfCoordinatorMock.addConsumer(subId, address(basketVrfConsumer));

        vm.startPrank(ORACLE_OWNER);
        // set tangibleWrapper to be real estate oracle on chainlink oracle.
        IPriceOracleExt(address(chainlinkRWAOracle)).setTangibleWrapperAddress(
            address(realEstateOracle)
        );
        vm.stopPrank();

        vm.startPrank(factoryOwner);
        // add feature to metadata contract
        ITNFTMetadataExt(address(metadata)).addFeatures(
            _asSingletonArrayUint(RE_FEATURE_1),
            _asSingletonArrayString("Beach Homes")
        );
        // add feature to TNFTtype in metadata contract
        ITNFTMetadataExt(address(metadata)).addFeaturesForTNFTType(
            RE_TNFTTYPE,
            _asSingletonArrayUint(RE_FEATURE_1)
        );
        vm.stopPrank();

        emit log_named_address("Oracle for category", address(priceManager.oracleForCategory(realEstateTnft)));

        assertEq(ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_1), true);
        emit log_named_bool("Fingerprint added:", (ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_1)));

        // labels
        vm.label(address(factoryV2), "FACTORY");
        vm.label(address(realEstateTnft), "RealEstate_TNFT");
        vm.label(address(realEstateOracle), "RealEstate_ORACLE");
        vm.label(address(chainlinkRWAOracle), "CHAINLINK_ORACLE");
        vm.label(address(marketplace), "MARKETPLACE");
        vm.label(address(factoryProvider), "FACTORY_PROVIDER");
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(basket), "BASKET");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
        vm.label(address(vrfCoordinatorMock), "MOCK_VRF_COORDINATOR");
        vm.label(address(basketVrfConsumer), "BASKET_VRF_CONSUMER");
        vm.label(JOE, "JOE");
        vm.label(NIK, "NIK");
        vm.label(ALICE, "ALICE");
        vm.label(BOB, "BOB");
    }


    // -------
    // Utility
    // -------

    /// @notice This method adds feature metadata to a tokenId on a tnft contract
    function _addFeatureToCategory(address _tnft, uint256 _tokenId, uint256[] memory _features) public {
        vm.prank(TANGIBLE_LABS);
        // add feature to tnft contract
        ITangibleNFTExt(_tnft).addMetadata(
            _tokenId,
            _features
        );
    }

    /// @notice Helper function for creating items and minting to a designated address.
    function _createItemAndMint(address tnft, uint256 _sellAt, uint256 _stock, uint256 _mintCount, uint256 _fingerprint, address _receiver) internal returns (uint256[] memory) {
        require(_mintCount >= _stock, "mint count must be gt stock");

        vm.startPrank(ORACLE_OWNER);
        // create new item with fingerprint.
        IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
            _fingerprint, // fingerprint
            _sellAt,      // weSellAt
            0,            // lockedAmount
            _stock,       // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        vm.stopPrank();

        vm.prank(TANGIBLE_LABS);
        ITangibleNFTExt(tnft).addFingerprints(_asSingletonArrayUint(_fingerprint));

        return _mintToken(tnft, _mintCount, _fingerprint, _receiver);
    }

    /// @notice Helper function for minting to a designated address.
    function _mintToken(address tnft, uint256 _mintCount, uint256 _fingerprint, address _receiver) internal returns (uint256[] memory) {
        uint256 preBal = IERC721(tnft).balanceOf(TANGIBLE_LABS);

        // create mint voucher for RE_FP_1
        IVoucher.MintVoucher memory voucher = IVoucher.MintVoucher(
            ITangibleNFT(tnft),  // token
            _mintCount,          // mintCount
            0,                   // price -> since token is going to vendor, dont need price
            TANGIBLE_LABS,       // vendor
            address(0),          // buyer
            _fingerprint,        // fingerprint
            true                 // sendToVender
        );

        // mint token
        vm.prank(TANGIBLE_LABS);
        uint256[] memory tokenIds = factoryV2.mint(voucher);
        assertEq(IERC721(tnft).balanceOf(TANGIBLE_LABS), preBal + _mintCount);

        // transfer token to NIK
        for (uint256 i; i < _mintCount; ++i) {
            vm.prank(TANGIBLE_LABS);
            IERC721(tnft).transferFrom(TANGIBLE_LABS, _receiver, tokenIds[i]);
        }
        assertEq(IERC721(tnft).balanceOf(TANGIBLE_LABS), preBal);

        return tokenIds;
    }

    /// @notice helper function for adding new categories and deploying new TNFT addresses.
    function _deployNewTnftContract(string memory name) internal returns (address) {

        // Deploy TangibleNFTV2 -> for real estate
        vm.prank(TANGIBLE_LABS);
        ITangibleNFT tnft = IFactoryExt(address(factoryV2)).newCategory(
            name,  // Name
            "RLTY",     // Symbol
            "",         // Metadata base uri
            false,      // storage price fixed
            false,      // storage required
            address(realEstateOracle), // oracle address
            false,      // symbol in uri
            RE_TNFTTYPE    // tnft type
        );

        return address(tnft);
    }

    /// @notice This method runs through the same USDValue logic as the Basket::depositTNFT
    function _getUsdValueOfNft(address _tnft, uint256 _tokenId) internal view returns (uint256 usdValue) {
        
        // ~ get Tnft Native Value ~
        
        // fetch fingerprint of product/property
        uint256 fingerprint = ITangibleNFT(_tnft).tokensFingerprint(_tokenId);
        // using fingerprint, fetch the value of the property in it's respective currency
        (uint256 value, uint256 currencyNum) = realEstateOracle.marketPriceNativeCurrency(fingerprint);
        // Fetch the string ISO code for currency
        string memory currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));
        // get decimal representation of property value
        uint256 oracleDecimals = realEstateOracle.decimals();
        
        // ~ get USD Exchange rate ~

        // fetch price feed contract for native currency
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(currency);
        // from the price feed contract, fetch most recent exchange rate of native currency / USD
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // get decimal representation of exchange rate
        uint256 priceDecimals = priceFeed.decimals();
 
        // ~ get USD Value of property ~

        // calculate total USD value of property
        usdValue = (uint(price) * value * 10 ** 18) / 10 ** priceDecimals / 10 ** oracleDecimals;
    }


    // ----------
    // Unit Tests
    // ----------


    // TODO:
    // a. deposit testing with multiple TNFT addresses and multiple tokens for each TNFT contract
    //    - test deposit and batch deposits with fuzzing
    //    - again, but with rent accruing -> changing share price
    // b. stress test fulfillRandomRedeem
    //    - 1000+ depositedTnfts
    //    - tokensInBudget.length == depositedTnfts.length when > 1000 or smaller
    // c. stress test _redeemRent
    //    - 10-100+ tnftsSupported
    //    - refactor iterating thru claimable rent array and test multiple iterations with 100-1000+ TNFTs
    // d. multiple baskets


    // ~ stress depositTNFT ~

    /// @notice Stress test of depositTNFT method.
    function test_stress_depositTNFT() public {
        
        // ~ Config ~

        uint256 newCategories = 10;
        uint256 amountFingerprints = 30;

        // NOTE: Amount of TNFTs == newCategories * amountFingerprints
        uint256 totalTokens = newCategories * amountFingerprints;

        uint256[] memory fingerprints = new uint256[](amountFingerprints);
        address[] memory tnfts = new address[](newCategories);

        // store all new fingerprints in array.
        for (uint256 i; i < amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        for (uint256 i; i < newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
        }

        // mint multiple tokens for each contract
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tnft,
                    100_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    fingerprints[j],
                    JOE
                );
                tokenIdMap[tnfts[i]].push(tokenIds[0]);

                assertEq(ITangibleNFT(tnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), amountFingerprints);
        }

        // ~ Pre-state check ~

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // ~ Execute depositTNFT and Assert ~

        // deposit all tokens
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < tokenIdMap[tnft].length; ++j) {

                uint256 tokenId = tokenIdMap[tnft][j];
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);
                uint256 basketPreBal = basket.balanceOf(JOE);

                // get usdValue of tnft and share price
                uint256 usdValue = _getUsdValueOfNft(tnft, tokenId);
                uint256 sharePrice = basket.getSharePrice();

                // Joe executed depositTNFT
                vm.startPrank(JOE);
                ITangibleNFT(address(tnft)).approve(address(basket), tokenId);
                basket.depositTNFT(address(tnft), tokenId);
                vm.stopPrank();

                // verify share price * balance == totalValueOfBasket
                assertEq(
                    (basket.balanceOf(JOE) * sharePrice) / 1 ether,
                    basket.getTotalValueOfBasket()
                );

                // verify basket now owns token
                assertEq(ITangibleNFT(tnft).ownerOf(tokenId), address(basket));
                assertEq(basket.tokenDeposited(tnft, tokenId), true);

                // verify Joe balances
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal - 1);
                assertEq(basket.balanceOf(JOE), basketPreBal + usdValue);
                assertEq(basket.totalSupply(), basket.balanceOf(JOE));
            }
        }

        // ~ Post-state check ~

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, totalTokens);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, newCategories);

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[0]);
        assertEq(tokenIdLib.length, amountFingerprints);

        uint256 count;
        for (uint256 i; i < tnftsSupported.length; ++i) {
            assertEq(tnftsSupported[i], tnfts[i]);

            uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[i]);
            assertEq(tokenIdLib.length, amountFingerprints);

            for (uint256 j; j < tokenIdLib.length; ++j) {
                uint256 tokenId = tokenIdMap[tnftsSupported[i]][j];
                assertEq(tokenIdLib[j], tokenId);

                assertEq(deposited[count].tnft, tnftsSupported[i]);
                assertEq(deposited[count].tokenId, tokenId);
                assertEq(deposited[count].fingerprint, j);
                ++count;
            }
        }

        // reset tokenIdMap
        for (uint256 i; i < newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }

    /// @notice Stress test of depositTNFT method using fuzzing.
    function test_stress_depositTNFT_fuzzing(uint256 _categories, uint256 _fps) public {
        _categories = bound(_categories, 1, 10);
        _fps = bound(_fps, 1, 20);

        // ~ Config ~

        uint256 newCategories = _categories;
        uint256 amountFingerprints = _fps;

        // NOTE: Amount of TNFTs == newCategories * amountFingerprints
        uint256 totalTokens = newCategories * amountFingerprints;

        uint256[] memory fingerprints = new uint256[](amountFingerprints);
        address[] memory tnfts = new address[](newCategories);

        // store all new fingerprints in array.
        for (uint256 i; i < amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        for (uint256 i; i < newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
        }

        // mint multiple tokens for each contract
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tnft,
                    100_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    fingerprints[j],
                    JOE
                );
                tokenIdMap[tnfts[i]].push(tokenIds[0]);

                assertEq(ITangibleNFT(tnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), amountFingerprints);
        }

        // ~ Pre-state check ~

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // ~ Execute depositTNFT and Assert ~

        // deposit all tokens
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < tokenIdMap[tnft].length; ++j) {

                uint256 tokenId = tokenIdMap[tnft][j];
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);
                uint256 basketPreBal = basket.balanceOf(JOE);

                // get usdValue of tnft and share price
                uint256 usdValue = _getUsdValueOfNft(tnft, tokenId);
                uint256 sharePrice = basket.getSharePrice();

                // Joe executed depositTNFT
                vm.startPrank(JOE);
                ITangibleNFT(address(tnft)).approve(address(basket), tokenId);
                basket.depositTNFT(address(tnft), tokenId);
                vm.stopPrank();

                // verify share price * balance == totalValueOfBasket
                assertEq(
                    (basket.balanceOf(JOE) * sharePrice) / 1 ether,
                    basket.getTotalValueOfBasket()
                );

                // verify basket now owns token
                assertEq(ITangibleNFT(tnft).ownerOf(tokenId), address(basket));
                assertEq(basket.tokenDeposited(tnft, tokenId), true);

                // verify Joe balances
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal - 1);
                assertEq(basket.balanceOf(JOE), basketPreBal + usdValue);
                assertEq(basket.totalSupply(), basket.balanceOf(JOE));
            }
        }

        // ~ Post-state check ~

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, totalTokens);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, newCategories);

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[0]);
        assertEq(tokenIdLib.length, amountFingerprints);

        uint256 count;
        for (uint256 i; i < tnftsSupported.length; ++i) {
            assertEq(tnftsSupported[i], tnfts[i]);

            uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[i]);
            assertEq(tokenIdLib.length, amountFingerprints);

            for (uint256 j; j < tokenIdLib.length; ++j) {
                uint256 tokenId = tokenIdMap[tnftsSupported[i]][j];
                assertEq(tokenIdLib[j], tokenId);

                assertEq(deposited[count].tnft, tnftsSupported[i]);
                assertEq(deposited[count].tokenId, tokenId);
                assertEq(deposited[count].fingerprint, j);
                ++count;
            }
        }

        // reset tokenIdMap
        for (uint256 i; i < newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }
}