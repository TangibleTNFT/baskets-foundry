// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

// oz imports
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// chainlink imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// tangible imports
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { ITangibleNFT, ITangibleNFTExt } from "@tangible/interfaces/ITangibleNFT.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";

/**
 * @title CurrencyCalculator
 * @author Chase Brown
 * @notice This method acts as an API that allows basket contracts to fetch token value in it's
 *         native currency. Also allows baskets to convert currencies given most current FX Rates.
 */
contract CurrencyCalculator is UUPSUpgradeable, FactoryModifiers {

    /// @notice Stores the max amount of time an oracle price is allowed to go stale.
    uint256 public exchangeRateOracleMaxAge;
    /// @notice Stores the max amount of time a TNFT pricing oracle is allowed to go stale.
    uint256 public priceOracleMaxAge;

    /// @notice Emitted when exchangeRateOracleMaxAge is updated.
    event ExchangeRateOracleMaxAgeUpdated(uint256 newOracleMaxAge);
    /// @notice Emitted when priceOracleMaxAge is updated.
    event PriceOracleMaxAgeUpdated(uint256 newOracleMaxAge);

    /// @dev Error emitted when an oracle price that is fetched is stale.
    error StalePriceFromOracle(address oracle, uint256 updatedAt);
    /// @dev Error emitted when the exchange rate fetched is 0.
    error ZeroPrice();
    /// @dev Emitted when an input variable is equal to 0.
    error ZeroValue();

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract.
     * @param _factory Address to assign to `factory`.
     * @param initialOracleMaxAge Amount of time until we declare an oracle price "stale".
     */
    function initialize(address _factory, uint256 initialOracleMaxAge, uint256 initialPriceOracleMaxAge) external initializer {
        __FactoryModifiers_init(_factory);
        exchangeRateOracleMaxAge = initialOracleMaxAge;
        priceOracleMaxAge = initialPriceOracleMaxAge;
    }

    /**
     * @notice Allows factory owner to update the maximum oracle age for an exchange rate oracle.
     * @param newMaxAge New maximum age we allow an oracle price to be.
     */
    function updateExchangeRateOracleMaxAge(uint256 newMaxAge) external onlyFactoryOwner {
        if (newMaxAge == 0) revert ZeroValue();
        emit ExchangeRateOracleMaxAgeUpdated(newMaxAge);
        exchangeRateOracleMaxAge = newMaxAge;
    }

    /**
     * @notice Allows factory owner to update the maximum oracle age for a TNFT price oracle.
     * @param newMaxAge New maximum age we allow an oracle price to be.
     */
    function updatePriceOracleMaxAge(uint256 newMaxAge) external onlyFactoryOwner {
        if (newMaxAge == 0) revert ZeroValue();
        emit PriceOracleMaxAgeUpdated(newMaxAge);
        priceOracleMaxAge = newMaxAge;
    }

    /**
     * @dev Get $USD Value of specified token.
     * @param _tangibleNFT TNFT contract address.
     * @param _tokenId TokenId of token.
     * @return $USD value of token, note: base 1e18
     */
    function getUSDValue(address _tangibleNFT, uint256 _tokenId) public view returns (uint256) {
        (string memory currency, uint256 amount, uint8 nativeDecimals) = getTnftNativeValue(
            _tangibleNFT, ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId)
        );
        (uint256 rate, uint256 rateDecimals) = getUsdExchangeRate(currency);
        return (rate * amount * 10 ** 18) / 10 ** rateDecimals / 10 ** nativeDecimals;
    }

    /**
     * @dev Get value of TNFT in native currency.
     * @param _tangibleNFT TNFT contract address of token.
     * @param _fingerprint fingerprint of token.
     * @return currency -> ISO code of native currency. (i.e. "GBP")
     * @return value -> Value of token in native currency.
     * @return decimals -> Amount of decimals used for precision.
     */
    function getTnftNativeValue(address _tangibleNFT, uint256 _fingerprint) public view returns (string memory currency, uint256 value, uint8 decimals) {
        IPriceOracle oracle = _getOracle(_tangibleNFT);

        uint256 lastUpdate = oracle.latestTimeStamp(_fingerprint);
        if (block.timestamp > lastUpdate + priceOracleMaxAge) revert StalePriceFromOracle(address(oracle), lastUpdate);

        uint256 currencyNum;
        (value, currencyNum) = oracle.marketPriceNativeCurrency(_fingerprint);
        require(currencyNum <= type(uint16).max, "currencyNum not within uint16 bounds");
        if (value == 0) revert ZeroPrice();

        ICurrencyFeedV2 currencyFeed = ICurrencyFeedV2(IFactory(factory()).currencyFeed());
        currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));

        decimals = oracle.decimals();
    }

    /**
     * @dev Get USD Price of given currency from ChainLink.
     * @param _currency Currency ISO code.
     * @return exchangeRate rate.
     * @return decimals used for precision on priceFeed.
     */
    function getUsdExchangeRate(string memory _currency) public view returns (uint256 exchangeRate, uint256 decimals) {
        ICurrencyFeedV2 currencyFeed = ICurrencyFeedV2(IFactory(factory()).currencyFeed());
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(_currency);

        decimals = priceFeed.decimals();
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        if (block.timestamp > updatedAt + exchangeRateOracleMaxAge) revert StalePriceFromOracle(address(priceFeed), updatedAt);
        if (price == 0) revert ZeroPrice();

        exchangeRate = uint256(price) + currencyFeed.conversionPremiums(_currency);
    }

    /**
        * @param _tangibleNFT TNFT contract address we want the PriceOracle for.
     * @return PriceOracle contract reference.
     */
    function _getOracle(address _tangibleNFT) internal view returns (IPriceOracle) {
        ITangiblePriceManager priceManager = IFactory(factory()).priceManager();
        return ITangiblePriceManager(address(priceManager)).oracleForCategory(ITangibleNFT(_tangibleNFT));
    }

    /**
     * @notice Inherited from UUPSUpgradeable. Allows us to authorize the factory owner to upgrade this contract's implementation.
     */
    function _authorizeUpgrade(address) internal override onlyFactoryOwner {}
}