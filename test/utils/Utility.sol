// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { IChainlinkRWAOracle } from "@tangible/interfaces/IChainlinkRWAOracle.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { VRFCoordinatorV2Interface } from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract Utility is Test{

    // ~ RPCs ~

    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");


    // ~ Actors ~

    address public constant JOE     = address(bytes20(bytes("Joe")));
    address public constant NIK     = address(bytes20(bytes("Nik")));
    address public constant ALICE   = address(bytes20(bytes("Alice")));
    address public constant BOB     = address(bytes20(bytes("Bob")));
    address public constant CREATOR = address(bytes20(bytes("Creator")));

    address public constant ADMIN = address(bytes20(bytes("Admin")));
    address public constant REV_SHARE = address(bytes20(bytes("Revenue Share"))); // NOTE: temporary
    address public constant GELATO_OPERATOR = address(bytes20(bytes("Gelato Vrf Operator")));

    address public constant REBASE_INDEX_MANAGER = address(bytes20(bytes("Rebase Index Manager")));
    address public constant REBASE_CONTROLLER = address(bytes20(bytes("Rebase Controller")));


    // ~ Constants ~

    IERC20Metadata public constant MUMBAI_USTB = IERC20Metadata(0xbFB1dB179d9710Ed05F6dfCEd279205156EA3684);
    IERC20Metadata public constant MUMBAI_USDC = IERC20Metadata(0x667269618f67f543d3121DE3DF169747950Deb13); // 0x4b64cCe8Af0f1983fb990B152fb2Ff637d26B636
    IERC20Metadata public constant MUMBAI_DAI  = IERC20Metadata(0xf46c460F5B2D33aC5c4cE2aA015c8B5c430231C5); // 0x001B3B4d0F3714Ca98ba10F6042DaEbF0B1B7b6F

    IERC20Metadata public constant UNREAL_USDC = IERC20Metadata(0x2Fab7758c3efdf392e84e89ECe376952eb00aB2A);
    IERC20Metadata public constant UNREAL_DAI  = IERC20Metadata(0x3F93beBAd7BA4d7A5129eA8159A5829Eacb06497);
    IERC20Metadata public constant UNREAL_USTB = IERC20Metadata(0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD);

    uint256 public constant MUMBAI_CHAIN_ID = 80001;
    uint256 public constant UNREAL_CHAIN_ID = 18233;

    VRFCoordinatorV2Interface public constant MUMBAI_VRF_COORDINATOR = VRFCoordinatorV2Interface(0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed);
    VRFCoordinatorV2Interface public constant POLYGON_VRF_COORDINATOR = VRFCoordinatorV2Interface(0xAE975071Be8F8eE67addBC1A82488F1C24858067);

    /// @dev https://docs.chain.link/vrf/v2/subscription/supported-networks#polygon-matic-mainnet
    bytes32 public constant POLYGON_VRF_KEY_HASH = 0xd729dc84e21ae57ffb6be0053bf2b0668aa2aaf300a2a7b2ddf7dc0bb6e875a8; // 1000 gwei
    /// @dev https://docs.chain.link/vrf/v2/subscription/supported-networks#polygon-matic-mumbai-testnet
    bytes32 public constant MUMBAI_VRF_KEY_HASH = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f; // 500 gwei


    // ~ Precision ~

    uint256 constant USD = 10 ** 6;  // USDC precision decimals
    uint256 constant BTC = 10 ** 8;  // WBTC precision decimals
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;


    // ~ Types and Features ~

    uint16 public constant UK_ISO = 826;
    uint16 public constant US_ISO = 840;

    uint256 public constant RE_TNFTTYPE = 2;

    uint256 public constant RE_FINGERPRINT_1 = 2241;
    uint256 public constant RE_FINGERPRINT_2 = 2242;
    uint256 public constant RE_FINGERPRINT_3 = 2243;
    uint256 public constant RE_FINGERPRINT_4 = 2244;

    uint256 public constant RE_FEATURE_1 = 111111;
    uint256 public constant RE_FEATURE_2 = 222222;
    uint256 public constant RE_FEATURE_3 = 333333;
    uint256 public constant RE_FEATURE_4 = 444444;

    uint256 public constant GOLD_TNFTTYPE = 1;


    // ~ Events ~

    event log_named_bool(string key, bool val);


    // ~ Utility Functions ~

    function _createLabels() internal virtual {
        vm.label(JOE, "JOE");
        vm.label(NIK, "NIK");
        vm.label(ALICE, "ALICE");
        vm.label(BOB, "BOB");
        vm.label(CREATOR, "CREATOR");
    }

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayUint(uint256 element) internal pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    /// @notice Turns a single address to an array of uints of size 1.
    function _asSingletonArrayAddress(address element) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = element;

        return array;
    }

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayString(string memory element) internal pure returns (string[] memory) {
        string[] memory array = new string[](1);
        array[0] = element;

        return array;
    }

    /// @notice Verify equality within accuracy decimals.
    function assertWithinPrecision(uint256 val0, uint256 val1, uint256 accuracy) internal {
        uint256 diff  = val0 > val1 ? val0 - val1 : val1 - val0;
        if (diff == 0) return;

        uint256 denominator = val0 == 0 ? val1 : val0;
        bool check = ((diff * RAY) / denominator) < (RAY / 10 ** accuracy);

        if (!check){
            emit log_named_uint("Error: approx a == b not satisfied, accuracy digits ", accuracy);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }

    /// @notice Verify equality within difference.
    function assertWithinDiff(uint256 val0, uint256 val1, uint256 expectedDiff) internal {
        uint256 actualDiff = val0 > val1 ? val0 - val1 : val1 - val0;
        bool check = actualDiff <= expectedDiff;

        if (!check) {
            emit log_named_uint("Error: approx a == b not satisfied, accuracy difference ", expectedDiff);
            emit log_named_uint("Actual difference ", actualDiff);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }

}

/// @title interface for CounterContract -> beacon proxy testing
interface ICounterContract {
    function increment() external;
    function counter() external returns (uint256);
}

interface ITangibleNFTExt is ITangibleNFT {
    /// @dev Returns the feature status of a `tokenId`.
    function tokenFeatureAdded (uint256 tokenId, uint256 feature) external view returns (FeatureInfo memory);
    function getFingerprintsSize() external view returns (uint256);
    function getFingerprints() external view returns (uint256[] memory);
    function addMetadata(uint256 tokenId, uint256[] calldata _features) external;
    function removeMetadata(uint256 tokenId, uint256[] calldata _features) external;
    function fingerprintAdded(uint256) external returns (bool);
    function addFingerprints(uint256[] calldata fingerprints) external;
}

interface IPriceOracleExt {
    function updateStock(uint256 fingerprint, uint256 weSellAtStock) external;
    function setTangibleWrapperAddress(address oracle) external;
    function createItem(
        uint256 fingerprint,
        uint256 weSellAt,
        uint256 lockedAmount,
        uint256 weSellAtStock,
        uint16 currency,
        uint16 location
    ) external;
    function updateItem(uint256 fingerprint, uint256 weSellAt, uint256 lockedAmount) external;
    function chainlinkRWAOracle() external returns (IChainlinkRWAOracle);
}

interface IFactoryExt {
    enum FACT_ADDRESSES {
        MARKETPLACE,
        TNFT_DEPLOYER,
        RENT_MANAGER_DEPLOYER,
        LABS,
        PRICE_MANAGER,
        TNFT_META,
        REVENUE_SHARE,
        BASKETS_MANAGER,
        CURRENCY_FEED
    }

    function setRequireWhitelistCategory(ITangibleNFT tnft, bool required) external;

    function setContract(FACT_ADDRESSES _contractId, address _contractAddress) external;

    function newCategory(
        string calldata name,
        string calldata symbol,
        string calldata uri,
        bool isStoragePriceFixedAmount,
        bool storageRequired,
        address priceOracle,
        bool symbolInUri,
        uint256 _tnftType
    ) external returns (ITangibleNFT);
}

interface IPriceManagerExt {
    function oracleForCategory(ITangibleNFT) external returns (IPriceOracle);
}

interface ITNFTMetadataExt {
    function addFeatures(uint256[] calldata _featureList, string[] calldata _featureDescriptions) external;
    function addFeaturesForTNFTType(uint256 _tnftType, uint256[] calldata _features) external;
}