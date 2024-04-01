// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports

// chainlink imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// tangible imports
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
contract CurrencyCalculator {

    /// @notice Stores Factory address
    address public immutable factory;

    /**
     * @notice Initializes contract.
     * @param _factory Address to assign to `factory`.
     */
    constructor(address _factory) {
        factory = _factory;
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

        uint256 currencyNum;
        (value, currencyNum) = oracle.marketPriceNativeCurrency(_fingerprint);

        ICurrencyFeedV2 currencyFeed = ICurrencyFeedV2(IFactory(factory).currencyFeed());
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
        ICurrencyFeedV2 currencyFeed = ICurrencyFeedV2(IFactory(factory).currencyFeed());
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(_currency);

        decimals = priceFeed.decimals();
        (, int256 price, , , ) = priceFeed.latestRoundData();

        if (price > 0) exchangeRate = uint256(price) + currencyFeed.conversionPremiums(_currency);
    }

    /**
     * @notice This method is an internal view method that fetches the PriceOracle contract for a specified TNFT contract.
     * @param _tangibleNFT TNFT contract address we want the PriceOracle for.
     * @return PriceOracle contract reference.
     */
    function _getOracle(address _tangibleNFT) internal view returns (IPriceOracle) {
        ITangiblePriceManager priceManager = IFactory(factory).priceManager();
        return ITangiblePriceManager(address(priceManager)).oracleForCategory(ITangibleNFT(_tangibleNFT));
    }
}