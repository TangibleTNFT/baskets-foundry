// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// chainlink imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// tangible imports
import { RebaseTokenUpgradeable } from "@tangible-foundation-contracts/tokens/RebaseTokenUpgradeable.sol";
import { ITangibleNFT, ITangibleNFTExt } from "@tangible/interfaces/ITangibleNFT.sol";
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { IRentManager, IRentManagerExt } from "@tangible/interfaces/IRentManager.sol";
import { IRWAPriceNotificationReceiver } from "@tangible/notifications/IRWAPriceNotificationReceiver.sol";
import { IRWAPriceNotificationDispatcher } from "@tangible/interfaces/IRWAPriceNotificationDispatcher.sol";
import { INotificationWhitelister } from "@tangible/interfaces/INotificationWhitelister.sol";
import { IChainlinkRWAOracle } from "@tangible/interfaces/IChainlinkRWAOracle.sol";

// local imports
import { IBasket } from "./interfaces/IBasket.sol";
import { IBasketManager } from "./interfaces/IBasketManager.sol";
import { ICurrencyCalculator } from "./interfaces/ICurrencyCalculator.sol";
import { IBasketsVrfConsumer } from "./interfaces/IBasketsVrfConsumer.sol";
import { IGetNotificationDispatcher } from "./interfaces/IGetNotificationDispatcher.sol";
import { IGetOracle } from "./interfaces/IGetOracle.sol";


/**
 * @title Basket
 * @author Chase Brown
 * @notice ERC-20 token that represents a basket of ERC-721 TangibleNFTs that are categorized into "baskets".
 */
contract Basket is Initializable, RebaseTokenUpgradeable, IBasket, IRWAPriceNotificationReceiver, ReentrancyGuardUpgradeable, FactoryModifiers {
    using SafeERC20 for IERC20Metadata;

    // ---------------
    // State Variables
    // ---------------

    /// @notice Ledger of all TNFT tokens stored in this basket.
    TokenData[] public depositedTnfts;

    /// @notice Tracks the index of each tokenId in the `depositedTnfts` array.
    mapping(address tnft => mapping(uint256 tokenId => uint256 index)) public indexInDepositedTnfts;

    /// @notice This stores the data for the next NFT that is elgible for redemption.
    RedeemData public nextToRedeem;

    /// @notice Array of currencies that the basket currently holds or supports.
    string[] public supportedCurrencies;

    /// @notice Array of TNFT contract addresses supported by this contract.
    address[] public tnftsSupported;

    /// @notice Array of all features required by a TNFT token to be deposited into this basket.
    /// @dev These features (aka "subcategories") are OPTIONAL.
    uint256[] public supportedFeatures;

    /// @notice Mapping of TNFT contract address => array of tokenIds in this basket from each TNFT contract.
    mapping(address => uint256[]) public tokenIdLibrary;

    /// @notice Tracks index of where the tokenId for the tnft exists in `tokenIdLibrary` array.
    mapping(address tnft => mapping(uint256 tokenId => uint256 index)) public indexInTokenIdLibrary;

    /// @notice TangibleNFT contract => tokenId => if deposited into address(this).
    mapping(address => mapping(uint256 => bool)) public tokenDeposited;

    /// @notice Mapping used to check whether a specified feature (key) is supported. If true, feature is required.
    mapping(uint256 => bool) public featureSupported;

    /// @notice Mapping used to store address that can withdraw rent from this contract.
    mapping(address => bool) public canWithdraw;

    /// @notice Stores trusted targets for reinvesting rent.
    mapping(address => bool) public trustedTarget;

    /// @notice If true, currency exists in `supportedCurrencies`.
    mapping(string => bool) public currencySupported;

    /// @notice Decimals oracle uses for currency.
    mapping(string => uint8) public currencyDecimals;

    /// @notice TnftType that this basket supports exclusively.
    /// @dev This TnftType (aka "category") is REQUIRED upon basket creation.
    uint256 public tnftType;

    /// @notice This value is used to track the total raw value (i.e. GBP) of all TNFT tokens inside this contract by currency.
    mapping(string => uint256) public totalNftValueByCurrency;

    /// @notice This value stores the amount of rent claimable by this contract. Updated upon rebase.
    uint256 public totalRentValue;

    /// @notice If there is a pending, unfulfilled, Gelato vrf request, the requestId will be stored here.
    uint256 public pendingSeedRequestId;

    /// @notice Stores the timestamp of when the last rebase occured.
    uint256 public lastRebaseTimestamp;

    /// @notice This stores a reference to the primary ERC-20 token used for paying out rent.
    IERC20Metadata public primaryRentToken; // USTB by default

    /// @notice Address of basket creator.
    address public deployer;

    /// @notice Address of rebase manager.
    address public rebaseIndexManager;

    /// @notice Address of BasketManager
    address public basketManager;

    /// @notice Stores amount of NFTs that are allowed to be inside basket at one time.
    uint24 public cap;

    /// @notice Stores the fee taken upon a deposit. Uses 2 basis points (i.e. 2% == 200)
    uint16 public depositFee; // 0.5% by default

    /// @notice Stores the fee taken upon a deposit. Uses 2 basis points (i.e. 10% == 1000)
    uint16 public rentFee; // 10% by default

    /// @notice Stores the ISO country code for location this basket supports.
    uint16 public location;

    /// @notice If true, there is an outstanding request to Gelato vrf that has yet to be fulfilled.
    bool public seedRequestInFlight;


    // ---------
    // Modifiers
    // ---------

    /// @notice This modifier is to verify msg.sender is the BasketVrfConsumer constract.
    modifier onlyBasketVrfConsumer() {
        if (msg.sender != _getBasketVrfConsumer()) revert NotAuthorized(msg.sender);
        _;
    }

    /// @notice This modifier is to verify msg.sender has the ability to withdraw rent.
    modifier onlyCanWithdraw() {
        if (!canWithdraw[msg.sender]) revert NotAuthorized(msg.sender);
        _;
    }


    // -----------
    // Constructor
    // -----------

    constructor() {
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    /**
     * @notice Initializes Basket contract.
     * @param _name Unique name of basket contract.
     * @param _symbol Unique symbol of basket contract.
     * @param _factoryProvider FactoryProvider contract address.
     * @param _tnftType TNFT Type (category).
     * @param _rentToken ERC-20 token being used for rent. USTB by default.
     * @param _features Array of features TNFTs must support to be in this basket.
     * @param _location ISO country code for supported location of basket.
     * @param _deployer Address of creator of the basket contract.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _factoryProvider,
        uint256 _tnftType,
        address _rentToken,
        bool _isRebaseToken,
        uint256[] memory _features,
        uint16 _location,
        address _deployer
    ) external initializer {   
        if (_factoryProvider == address(0)) revert ZeroAddress();

        __RebaseToken_init(_name, _symbol);
        __FactoryModifiers_init(_factoryProvider);
        __ReentrancyGuard_init();
        
        // If _features is not empty, add features
        for (uint256 i; i < _features.length; ++i) {
            uint256 feature = _features[i];
            supportedFeatures.push(feature);
            featureSupported[feature] = true;
        }

        depositFee = 50; // 0.5%
        rentFee = 10_00; // 10.0%
        cap = 500;

        location = _location;
        basketManager = msg.sender;

        _setRebaseIndex(1 ether);

        tnftType = _tnftType;
        deployer = _deployer;

        _updatePrimaryRentToken(_rentToken, _isRebaseToken);
        canWithdraw[IOwnable(factory()).owner()] = true;
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method allows a user to deposit a batch of TNFTs into the basket.
     * @dev Gas block limit is reached at ~200 tokens.
     * @param _tangibleNFTs Array of TNFT contract addresses corresponding with each token being deposited.
     * @param _tokenIds Array of token Ids being deposited.
     * @return basketShares -> Array of basket tokens minted to msg.sender for each token deposited.
     */
    function batchDepositTNFT(address[] memory _tangibleNFTs, uint256[] memory _tokenIds) external returns (uint256[] memory basketShares) {
        uint256 length = _tangibleNFTs.length;
        if (length != _tokenIds.length) revert NotSameSize();

        basketShares = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            basketShares[i] = _depositTNFT(_tangibleNFTs[i], _tokenIds[i], msg.sender);
        }
    }

    /**
     * @notice This method allows a user to deposit their TNFT in exchange for Basket tokens.
     * @param _tangibleNFT TNFT contract address of token being deposited.
     * @param _tokenId TNFT tokenId of token being deposited.
     * @return basketShare -> Amount of basket tokens minted to msg.sender.
     */
    function depositTNFT(address _tangibleNFT, uint256 _tokenId) external returns (uint256 basketShare) {
        basketShare = _depositTNFT(_tangibleNFT, _tokenId, msg.sender);
    }

    /**
     * @notice This method is used to redeem a TNFT token. This method will take a budget of basket tokens and
     *         if the budget is sufficient will transfer the NFT stored in `nextToRedeem` to the msg.sender.
     * @dev Burns basket tokens 1-1 with usdValue of token redeemed.
     * @param _budget Amount of basket tokens being submitted to redeem method.
     * @param _desiredToken Tnft address and tokenId encoded as bytes32.
     */
    function redeemTNFT(uint256 _budget, bytes32 _desiredToken) external {
        _redeemTNFT(msg.sender, _budget, _desiredToken);
    }

    /**
     * @notice This method is executed upon the callback of vrf for entropy. This method will use the randomWord to select
     *         a ranom index from the `depositedTnfts` array to be next redeemable NFT.
     * @param randomWord Random uint seed received from vrf.
     */
    function fulfillRandomSeed(uint256 randomWord) external onlyBasketVrfConsumer {
        // if there is already an NFT to be redeemed, do not re-roll
        seedRequestInFlight = false;
        pendingSeedRequestId = 0;

        if(nextToRedeem.tnft != address(0)) return;

        // choose a nft to be next redeemable
        uint256 index = randomWord % depositedTnfts.length;

        TokenData memory depositedTnft = depositedTnfts[index];
        address tnft = depositedTnft.tnft;
        uint256 tokenId = depositedTnft.tokenId;

        nextToRedeem = RedeemData(tnft, tokenId);
        emit RedeemableChosen(tnft, tokenId);
    }

    /**
     * @notice This method allows the factory owner to manually send a request for entropy to vrf.
     * @dev This method should only be used as a last resort if a vrf callback reverts or if there resides a stale redeemable.
     * @return requestId -> request identifier created by vrf coordinator.
     */
    function sendRequestForSeed() external onlyFactoryOwner returns (uint256 requestId) {
        return _sendRequestForSeed();
    }

    /**
     * @notice Allows this contract to get notified of a price change
     * @dev Defined on interface IRWAPriceNotificationReceiver::notify
     * @param _tnft TNFT contract address of token being updated.
     * @param _tokenId TNFT tokenId of token being updated.
     * @param _oldNativePrice Old price of the token, native currency.
     * @param _newNativePrice New price of the token, native currency.
     * @param _currency Currency ISO.
     */
    function notify(
        address _tnft,
        uint256 _tokenId,
        uint256 /* fingerprint */,
        uint256 _oldNativePrice,
        uint256 _newNativePrice,
        uint16  _currency
    ) external {
        if (msg.sender != address(_getNotificationDispatcher(_tnft))) revert NotAuthorized(msg.sender);

        // get string code from num code
        string memory currency = ICurrencyFeedV2(IFactory(factory()).currencyFeed()).ISOcurrencyNumToCode(_currency);
        // update `totalNftValueByCurrency`
        uint256 nativeValue = totalNftValueByCurrency[currency];
        nativeValue = (nativeValue - _oldNativePrice) + _newNativePrice;
        totalNftValueByCurrency[currency] = nativeValue;

        emit PriceNotificationReceived(_tnft, _tokenId, _oldNativePrice, _newNativePrice);
    }

    /**
     * @notice This method allows the factory owner to update the `primaryRentToken` state variable.
     * @dev If the rent token is being changed indefinitely, make sure to change the address of the rent token being used
     *      to initialize new baskets on the BasketManager.
     * @param _primaryRentToken New address for `primaryRentToken`.
     * @param _isRebaseToken If `_primaryRentToken` is a rebase token, this must be true.
     * @dev If the new rent token is a rebase token, this contract will need to opt out of rebasing. By setting
     * `_isRebaseToken` to true, this contract will call disableRebase via a low level call.
     */
    function updatePrimaryRentToken(address _primaryRentToken, bool _isRebaseToken) external nonReentrant onlyFactoryOwner {
        if (_primaryRentToken == address(0)) revert ZeroAddress();
        _updatePrimaryRentToken(_primaryRentToken, _isRebaseToken);
    }

    /**
     * @notice This setter allows the factory owner to update the `rebaseIndexManager` state variable.
     * @param _rebaseIndexManager Address of rebase manager.
     */
    function updateRebaseIndexManager(address _rebaseIndexManager) external {
        if (
            msg.sender != IOwnable(factory()).owner() && 
            msg.sender != IBasketManager(basketManager).rebaseController()
        ) revert NotAuthorized(msg.sender);
        rebaseIndexManager = _rebaseIndexManager;
    }

    /**
     * @notice This method allows the factory owner to manipulate the rent fee taken during rebase.
     * @dev This fee is defaulted to 10_00 == 10%.
     *      Should only be used in serious cases when updating rent tokens and resetting rebaseIndex.
     * @param _rentFee New rent fee.
     */
    function updateRentFee(uint16 _rentFee) external onlyFactoryOwner {
        if (_rentFee > 50_00) revert FeeTooHigh(_rentFee);
        emit RentFeeUpdated(_rentFee);
        rentFee = _rentFee;
    }

    /**
     * @notice This method allows the factory owner to update the basket cap.
     * @dev By default this cap is 500 tokens. The cap is the amount of NFTs that are allowed to be in
     *      the basket at any given time.
     * @param _cap New cap;
     */
    function updateCap(uint24 _cap) external onlyFactoryOwner {
        emit CapUpdated(_cap);
        cap = _cap;
    }

    /**
     * @notice This method adds a `target` and value to `trustedTarget`.
     * @dev If the `target` is trusted, it can be used to send funds to in `reinvestRent`.
     * @param target Target address.
     * @param value If true, is a trusted address.
     */
    function addTrustedTarget(address target, bool value) external onlyFactoryOwner {
        if (target == address(0)) revert ZeroAddress();
        emit TrustedTargetAdded(target, value);
        trustedTarget[target] = value;
    }

    /**
     * @notice This method allows the factory owner to give permission to another address to withdraw rent.
     * @param account Address being granted or not granted permission to withdraw
     * @param hasRole If true, address can call `withdrawRent`.
     */
    function setWithdrawRole(address account, bool hasRole) external onlyFactoryOwner {
        if (account == address(0)) revert ZeroAddress();
        emit WithdrawRoleGranted(account, hasRole);
        canWithdraw[account] = hasRole;
    }

    /**
     * @notice This method allows a permissioned address to withdraw a specified amount of claimable rent from this basket.
     * @param _withdrawAmount Amount of rent to withdraw.
     */
    function withdrawRent(uint256 _withdrawAmount) external nonReentrant onlyCanWithdraw {
        _transferRent(msg.sender, _withdrawAmount);
    }

    /**
     * @notice This method is used to quote a batch amount of basket tokens transferred to depositor if a specfied token is deposted.
     * @dev Does NOT include the amount of basket tokens subtracted for deposit fee.
     *      The amount of tokens quoted will be slightly different if the same tokens are deposited via batchDepositTNFT.
     *      Reason being, when tokens are deposited sequentially via batch, the share price will fluctuate in between deposits.
     * @param _tangibleNFTs Array of TangibleNFT contract addresses of NFTs being quoted.
     * @param _tokenIds Array of TokenIds of NFTs being quoted.
     * @return shares -> Array of Erc20 basket tokens quoted for each NFT respectively.
     */
    function getBatchQuoteIn(address[] memory _tangibleNFTs, uint256[] memory _tokenIds) external view returns (uint256[] memory shares) {
        uint256 len = _tangibleNFTs.length;
        uint256 depFee = uint256(depositFee);
        shares = new uint256[](len);
        for (uint i; i < len; ++i) {
            // calculate usd value of TNFT with 18 decimals
            uint256 usdValue = getUSDValue(_tangibleNFTs[i], _tokenIds[i]);

            // calculate shares for depositor
            uint256 share = _quoteShares(usdValue);

            unchecked {
                uint256 fee = (share * depFee) / 100_00;
                shares[i] = share - fee;
            }
        }
    }

    /**
     * @notice This method is used to quote an amount of basket tokens transferred to depositor if a specfied token is deposted.
     * @dev Does NOT include the amount of basket tokens subtracted for deposit fee.
     * @param _tangibleNFT TangibleNFT contract address of NFT being quoted.
     * @param _tokenId TokenId of NFT being quoted.
     * @return shares -> Amount of Erc20 basket tokens quoted for NFT.
     */
    function getQuoteIn(address _tangibleNFT, uint256 _tokenId) external view returns (uint256 shares) {
        // calculate usd value of TNFT with 18 decimals
        uint256 usdValue = getUSDValue(_tangibleNFT, _tokenId);

        // calculate shares for depositor
        shares = _quoteShares(usdValue);

        uint256 fee = (shares * uint256(depositFee)) / 100_00;
        shares -= fee;
    }

    /**
     * @notice This method is used to quote an amount of basket tokens required if a specfiied token is redeemed.
     * @param _tangibleNFT TangibleNFT contract address of NFT being quoted.
     * @param _tokenId TokenId of NFT being quoted.
     * @return sharesRequired -> Amount of Erc20 basket tokens required to redeem NFT.
     */
    function getQuoteOut(address _tangibleNFT, uint256 _tokenId) external view returns (uint256 sharesRequired) {
        // fetch usd value of tnft
        uint256 usdValue = getUSDValue(_tangibleNFT, _tokenId);

        // Get shares required
        sharesRequired = _quoteShares(usdValue);
    }

    /**
     * @notice Enables or disables rebasing for a specific account.
     * @dev This function can be called by either the account itself or the rebase index manager.
     * @param account The address of the account for which rebasing is to be enabled or disabled.
     * @param disable A boolean flag indicating whether to disable (true) or enable (false) rebasing for the account.
     */
    function disableRebase(address account, bool disable) external {
        if (msg.sender != account && msg.sender != rebaseIndexManager) revert NotAuthorized(msg.sender);
        _disableRebase(account, disable);
    }

    /**
     * @notice This method allows the factory owner to claim rent on behalf of the basket. 
     * @dev This only moves assets from the RentManager to the basket. Basket rent value does not change.
     * When rent is inside the basket vs in the RentManager, it makes performing _transfer rent much easier.
     * @param tnft TangibleNFT contract address of NFT.
     * @param tokenId TokenId of NFT.
     */
    function claimRentForToken(address tnft, uint256 tokenId) external nonReentrant onlyFactoryOwner {
        IRentManager rentManager = _getRentManager(tnft);
        uint256 claimed = _claimRentForToken(rentManager, tokenId);
        if (claimed == 0) revert ClaimingError();
    }

    /**
     * @notice This method allows thew factory owner to reinvest accrued rent.
     * @dev Ideally `target` would be a contract and `data` would be a method that allows us to purchase another
     *      property and deposits it into the basket to yield more rent.
     *      It is recommended to rebase before calling this method so `totalRentValue` is up to date.
     * @param target Address of contract with reinvest mechanism.
     * @param rentBalance Amount of rent balance being allocated for reinvestment.
     * @param data calldata payload for function call.
     */
    function reinvestRent(
        address target,
        uint256 rentBalance,
        bytes calldata data
    ) external onlyCanWithdraw returns (uint256 amountUsed) {
        if (!trustedTarget[target]) revert InvalidTarget(target);

        uint256 preBal = primaryRentToken.balanceOf(address(this));
        uint256 basketValueBefore = getTotalValueOfBasket();
        primaryRentToken.forceApprove(target, rentBalance);

        (bool success,) = target.call(data);
        if (!success) revert LowLevelCallFailed(data);

        uint256 postBal = primaryRentToken.balanceOf(address(this));
        primaryRentToken.forceApprove(target, 0);

        amountUsed = preBal - postBal;
        totalRentValue -= amountUsed;

        if (basketValueBefore > getTotalValueOfBasket()) revert TotalValueDecreased();
    }

    /**
     * @notice This function allows for the Basket token to "rebase" and will update the multiplier based
     * on the amount of rent accrued by the basket tokens.
     */
    function rebase() external nonReentrant {
        if (msg.sender != rebaseIndexManager) revert NotAuthorized(msg.sender);

        uint256 previousRentalIncome = totalRentValue;
        uint256 totalRentalIncome = getRentBal();

        uint256 collectedRent = totalRentalIncome - previousRentalIncome;

        // Take 10% off collectedRent and send to revenue contract
        uint256 rentDistribution = (collectedRent * rentFee) / 100_00;
        collectedRent -= rentDistribution;

        uint256 rebaseIndexDelta = (collectedRent * decimalsDiff()) * 1e18 / getTotalValueOfBasket();

        uint256 rebaseIndex = rebaseIndex();

        rebaseIndex += rebaseIndexDelta;
        totalRentValue = totalRentalIncome;

        _transferRent(_getRevenueDistributor(), rentDistribution);
        _setRebaseIndex(rebaseIndex);

        lastRebaseTimestamp = block.timestamp;
        emit RebaseExecuted(msg.sender, totalRentValue, rebaseIndex);
    }

    /**
     * @notice View method that returns whether `account` has rebase disabled or enabled.
     * @param account Address of account we want to query is or is not receiving rebase.
     */
    function isRebaseDisabled(address account) external view returns (bool) {
        return _isRebaseDisabled(account);
    }

    /**
     * @notice This method returns the `depositedTnfts` state array in it's entirety.
     */
    function getDepositedTnfts() external view returns (TokenData[] memory) {
        return depositedTnfts;
    }

    /**
     * @notice This method returns the `tnftsSupported` state array in it's entirety.
     */
    function getTnftsSupported() external view returns (address[] memory) {
        return tnftsSupported;
    }

    /**
     * @notice This method returns the `tokenIdLibrary` mapped array in it's entirety.
     * @param _tnft TNFT contract address specifying the array desired from the mapping.
     */
    function getTokenIdLibrary(address _tnft) external view returns (uint256[] memory) {
        return tokenIdLibrary[_tnft];
    }

    /**
     * @notice This method returns the `supportedFeatures` state array in it's entirety.
     */
    function getSupportedFeatures() external view returns (uint256[] memory) {
        return supportedFeatures;
    }

    /**
     * @notice This method returns the `supportedCurrencies` array in it's entirety.
     */
    function getSupportedCurrencies() external view returns (string[] memory) {
        return supportedCurrencies;
    }

    /**
     * @notice Return the USD value of share token for underlying assets, 18 decimals
     * @dev Underyling assets = TNFT + Accrued revenue
     */
    function getSharePrice() external view returns (uint256 sharePrice) {
        uint256 ts = totalSupply();
        if (ts == 0) {
            // initial share price is $100
            return 100 * 1e18;
        }

        sharePrice = (getTotalValueOfBasket() * 10 ** decimals()) / ts;
    }


    // --------------
    // Public Methods
    // --------------

    /**
     * @dev Get USD Value of specified token.
     * @param _tangibleNFT TNFT contract address.
     * @param _tokenId TokenId of token.
     * @return usdValue USD value of token, note: base 1e18
     */
    function getUSDValue(address _tangibleNFT, uint256 _tokenId) public view returns (uint256 usdValue) {
        usdValue = IBasketManager(basketManager).currencyCalculator().getUSDValue(_tangibleNFT, _tokenId);
        if (usdValue == 0) revert UnsupportedTNFT(_tangibleNFT, _tokenId);
    }

    /**
     * @notice This method returns the total value of NFTs and claimable rent in this basket contract.
     * @return totalValue -> total value in 18 decimals.
     */
    function getTotalValueOfBasket() public view returns (uint256 totalValue) {
        // get total value of nfts in basket by currency
        uint256 len = supportedCurrencies.length;
        for (uint256 i; i < len; ++i) {
            string memory currency = supportedCurrencies[i];
            uint256 nativeValue = totalNftValueByCurrency[currency];
            if (nativeValue != 0) {
                (uint256 price, uint256 priceDecimals) = IBasketManager(basketManager).currencyCalculator().getUsdExchangeRate(currency);
                totalValue += (price * nativeValue * 10 ** 18) / 10 ** priceDecimals / 10 ** currencyDecimals[currency];
            }
        }
        // get value of rent accrued by this contract.
        totalValue += totalRentValue * decimalsDiff();
    }

    /**
     * @notice This method returns the unclaimed rent balance of all TNFTs inside the basket.
     * @return totalRent -> Amount of claimable rent by from all TNFTs in this basket + rent in basket balance.
     */
    function getRentBal() public view returns (uint256 totalRent) {
        // iterate through all claimable rent for each tokenId in the contract.
        uint256 length = tnftsSupported.length;
        for (uint256 i; i < length; ++i) {
            address tnft = tnftsSupported[i];

            uint256 claimable = _getRentManager(tnft).claimableRentForTokenBatchTotal(tokenIdLibrary[tnft]);

            if (claimable > 0) {
                totalRent += claimable;
            }
        }

        totalRent += primaryRentToken.balanceOf(address(this));
    }

    /**
     * @notice This view method returns true if a specified token contains the features needed to be deposited into this basket.
     * @param _tangibleNFT TNFT contract address of token.
     * @param _tokenId TokenId of token.
     * @return If true, token is compatible and can be deposited into this basket contract.
     */
    function isCompatibleTnft(address _tangibleNFT, uint256 _tokenId) public view returns (bool) {
        // a. Check supported TNFTType (category)
        if (ITangibleNFTExt(_tangibleNFT).tnftType() != tnftType) return false;

        uint256 length = supportedFeatures.length;

        // b. Check supported features, if any (sub-category)
        for (uint256 i; i < length; ++i) {

            if (!ITangibleNFTExt(_tangibleNFT).tokenFeatureAdded(_tokenId, supportedFeatures[i]).added) {
                return false;
            }
        }

        // c. Check supported location, if any
        if (location != 0) {

            uint256 fingerprint = ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId);

            IChainlinkRWAOracle oracle = IGetOracle(address(_getOracle(_tangibleNFT))).chainlinkRWAOracle();
            IChainlinkRWAOracle.Data memory data = oracle.fingerprintData(fingerprint);

            return data.location == location;
        }

        return true;
    }

    /**
     * @notice This method provides an easy way to fetch the decimal difference between the `primaryRentToken` and
     *         the basket's native 18 decimals.
     * @return diff -> If the difference of decimals is gt 0, it will return 10**x (x being the difference).
     *         This can make converting basis points much easier. However, if the difference is == 0, will just return 1.
     */
    function decimalsDiff() public view returns (uint256 diff) {
        diff = decimals() - primaryRentToken.decimals();
        if (diff != 0) {
            return 10 ** diff;
        }
        else return 1;
    }


    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Internal method that handles making requests to vrf through the BasketsVrfConsumer contract.
     * @return requestId -> request identifier created by vrf coordinator.
     */
    function _sendRequestForSeed() internal returns (uint256 requestId) {
        if (depositedTnfts.length != 0) {
            seedRequestInFlight = true;

            requestId = IBasketsVrfConsumer(_getBasketVrfConsumer()).makeRequestForRandomWords();

            pendingSeedRequestId = requestId;
            emit RequestSentToVrf(requestId);
        }
    }

    /**
     * @notice Internal method for updating `primaryRentToken`.
     * @dev If new rent token is a rebase token, `_isRebaseToken` needs to be set to true. Baskets need to opt out of rebases
     * to keep rent redemption acounting secure and accurate.
     */
    function _updatePrimaryRentToken(address _primaryRentToken, bool _isRebaseToken) internal {
        primaryRentToken = IERC20Metadata(_primaryRentToken);
        if (_isRebaseToken) {
            bytes memory data = abi.encodeWithSignature("disableRebase(address,bool)", address(this), true);
            (bool success,) = _primaryRentToken.call(data);
            if (!success) revert LowLevelCallFailed(data);
        }
    }

    /**
     * @notice This internal method is used to deposit a specified TNFT from a depositor address to this basket.
     *         The deposit will be minted a sufficient amount of basket tokens in return.
     * @dev Any unclaimed rent claimable from the rent manager is claimed and transferred to the depositor.
     * @param _tangibleNFT TNFT contract address of token being deposited.
     * @param _tokenId TokenId of token being deposited.
     * @param _depositor Address depositing the token.
     * @return basketShare -> Amount of basket tokens being minted to redeemer.
     */
    function _depositTNFT(address _tangibleNFT, uint256 _tokenId, address _depositor) internal nonReentrant returns (uint256 basketShare) {
        if (tokenDeposited[_tangibleNFT][_tokenId]) revert TokenAlreadyDeposited(_tangibleNFT, _tokenId);

        // if contract supports features, make sure tokenId has a supported feature
        if (!isCompatibleTnft(_tangibleNFT, _tokenId)) revert TokenIncompatible(_tangibleNFT, _tokenId);

        // get token fingerprint
        uint256 fingerprint = ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId);

        // calculate usd value of TNFT with 18 decimals
        uint256 usdValue = getUSDValue(_tangibleNFT, _tokenId);

        // ~ Update contract state ~

        (string memory currency, uint256 amount, uint8 decimals) = _getTnftNativeValue(_tangibleNFT, fingerprint);

        if (!currencySupported[currency]) {
            currencySupported[currency] = true;
            currencyDecimals[currency] = decimals;
            supportedCurrencies.push(currency);
        }

        tokenDeposited[_tangibleNFT][_tokenId] = true;

        depositedTnfts.push(TokenData(_tangibleNFT, _tokenId, fingerprint));
        indexInDepositedTnfts[_tangibleNFT][_tokenId] = depositedTnfts.length - 1;

        if (depositedTnfts.length > cap) revert CapExceeded();

        tokenIdLibrary[_tangibleNFT].push(_tokenId);
        indexInTokenIdLibrary[_tangibleNFT][_tokenId] = tokenIdLibrary[_tangibleNFT].length - 1;

        (, bool exists) = _isSupportedTnft(_tangibleNFT);
        if (!exists) {
            tnftsSupported.push(_tangibleNFT);
        }

        // take token from depositor
        IERC721(_tangibleNFT).transferFrom(msg.sender, address(this), _tokenId);
        
        // register for price notifications
        IRWAPriceNotificationDispatcher notificationDispatcher = _getNotificationDispatcher(_tangibleNFT);

        if (!INotificationWhitelister(address(notificationDispatcher)).whitelistedReceiver(address(this))) revert NotWhitelisted();
        INotificationWhitelister(address(notificationDispatcher)).registerForNotification(_tokenId);

        // ~ Calculate basket tokens to mint ~

        // get quoted shares
        basketShare = _quoteShares(usdValue);

        // if msg.sender is basketManager, it's making an initial deposit -> receiver of basket tokens needs to be deployer.
        if (msg.sender == IFactory(factory()).basketsManager()) {
            _depositor = deployer;
        }

        // charge deposit fee.
        unchecked {
            uint256 feeShare = (basketShare * uint256(depositFee)) / 100_00;
            basketShare -= feeShare;
        }

        // ~ Handle rent ~

        // claim rent for TNFT being redeemed.
        IRentManager rentManager = _getRentManager(_tangibleNFT);

        if (rentManager.claimableRentForToken(_tokenId) != 0) {
            uint256 claimed = _claimRentForToken(rentManager, _tokenId);
            if (claimed == 0) revert ClaimingError();
            primaryRentToken.safeTransfer(address(_depositor), claimed);
        }

        // ~ Mint tokens to depositor ~

        // mint basket tokens to user
        _mint(_depositor, basketShare);

        // Update total nft value in this contract
        totalNftValueByCurrency[currency] += amount;

        // if there is no seed request in flight and no nextToRedeem, make request
        if (nextToRedeem.tnft == address(0) && !seedRequestInFlight) {
            if (depositedTnfts.length == 1) {
                // if first deposit, just assign first in to next redeem
                nextToRedeem = RedeemData(_tangibleNFT, _tokenId);
                emit RedeemableChosen(_tangibleNFT, _tokenId);
            }
            else {
                // if no request was made or fulfilled, but contract has more than 1 token in basket, send request.
                // could happen if request for entropy was made, but failed on callback
                _sendRequestForSeed();
            }
        }

        emit TNFTDeposited(_depositor, _tangibleNFT, _tokenId);
    }

    /**
     * @notice Internal method for redeeming a specified TNFT from this basket contract.
     * @param _redeemer EOA address of redeemer. note: msg.sender
     * @param _budget Budget of basket tokens willing to redeem
     * @param _token tnft address and tokenId encoded as bytes32
     */
    function _redeemTNFT(
        address _redeemer,
        uint256 _budget,
        bytes32 _token
    ) internal nonReentrant {
        if (_budget > balanceOf(_redeemer)) revert InsufficientBalance(balanceOf(_redeemer));
        if (seedRequestInFlight) revert SeedRequestPending();
        if (nextToRedeem.tnft == address(0)) revert NoneRedeemable();

        address _tangibleNFT = nextToRedeem.tnft;
        uint256 _tokenId = nextToRedeem.tokenId;
        uint256 _sharesRequired = _quoteShares(getUSDValue(_tangibleNFT, _tokenId));

        if (_token != keccak256(abi.encodePacked(_tangibleNFT, _tokenId))) revert TNFTNotRedeemable(_token);
        if (_sharesRequired > _budget) revert InsufficientBudget(_budget, _sharesRequired);

        delete nextToRedeem;

        // update contract
        tokenDeposited[_tangibleNFT][_tokenId] = false;

        uint256 index = indexInDepositedTnfts[_tangibleNFT][_tokenId];
        uint256 len = depositedTnfts.length - 1;
        delete indexInDepositedTnfts[_tangibleNFT][_tokenId];
        if (index != len) {
            depositedTnfts[index] = depositedTnfts[len];
            indexInDepositedTnfts[depositedTnfts[index].tnft][depositedTnfts[index].tokenId] = index;
        }
        depositedTnfts.pop();

        index = indexInTokenIdLibrary[_tangibleNFT][_tokenId];
        len = tokenIdLibrary[_tangibleNFT].length - 1;
        delete indexInTokenIdLibrary[_tangibleNFT][_tokenId];
        if (index != len) {
            tokenIdLibrary[_tangibleNFT][index] = tokenIdLibrary[_tangibleNFT][len];
            indexInTokenIdLibrary[_tangibleNFT][tokenIdLibrary[_tangibleNFT][index]] = index;
        }
        tokenIdLibrary[_tangibleNFT].pop();

        if (tokenIdLibrary[_tangibleNFT].length == 0) {
            len = tnftsSupported.length - 1;
            (index,) = _isSupportedTnft(_tangibleNFT);
            if (index != len) {
                tnftsSupported[index] = tnftsSupported[len];
            }
            tnftsSupported.pop();
        }

        IRentManager rentManager = _getRentManager(_tangibleNFT);

        // redeem rent from redeemed TNFT to this contract.
        if (rentManager.claimableRentForToken(_tokenId) > 0) {
            uint256 claimed = _claimRentForToken(rentManager, _tokenId);
            if (claimed == 0) revert ClaimingError();
        }

        // unregister from price notifications
        IRWAPriceNotificationDispatcher notificationDispatcher = _getNotificationDispatcher(_tangibleNFT);
        INotificationWhitelister(address(notificationDispatcher)).unregisterForNotification(_tokenId);

        (string memory currency, uint256 amount, /*uint8 nativeDecimals*/) = _getTnftNativeValue(
            _tangibleNFT, ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId)
        );
        totalNftValueByCurrency[currency] -= amount;

        _burn(_redeemer, _sharesRequired);

        // Transfer tokenId to user
        IERC721(_tangibleNFT).transferFrom(address(this), _redeemer, _tokenId);

        // fetch new seed
        _sendRequestForSeed();

        emit TNFTRedeemed(_redeemer, _tangibleNFT, _tokenId);
    }

    /**
     * @notice This method will transfer an arbitrary amount of `primaryRentToken` to a specified recipient.
     * @dev Will claim any rent from the rent manager that is needed if balanceOf(address(this)) is not sufficient.
     * @param _recipient Recipient of `primaryRentToken`.
     * @param _withdrawAmount Amount of `primaryRentToken` to transfer to `_recipient`.
     */
    function _transferRent(address _recipient, uint256 _withdrawAmount) internal {
        if (_withdrawAmount > totalRentValue) revert AmountExceedsWithdrawable(_withdrawAmount, totalRentValue);

        // if we still need more rent, start claiming rent from TNFTs in basket.
        if (_withdrawAmount > primaryRentToken.balanceOf(address(this))) {

            // iterate through all TNFT contracts supported by this basket.
            uint256 supportedLength = tnftsSupported.length;
            for (uint256 i; i < supportedLength; ++i) {
                address tnft = tnftsSupported[i];
                IRentManager rentManager = _getRentManager(tnft);

                uint256[] memory claimableAmounts = rentManager.claimableRentForTokenBatch(tokenIdLibrary[tnft]);

                // iterate through all claimable rent and claim rent for each tokenId
                uint256 tokenIdsLength = tokenIdLibrary[tnft].length;
                for (uint256 j; j < tokenIdsLength; ++j) {
                    uint256 tokenId = tokenIdLibrary[tnft][j];

                    if (claimableAmounts[j] > 0) {
                        uint256 claimed = _claimRentForToken(rentManager, tokenId);
                        if (claimed == 0) revert ClaimingError();
                    }
                }
                // if total amount in balance is sufficient, break loop and transfer to recipient.
                if (primaryRentToken.balanceOf(address(this)) >= _withdrawAmount) break;
            }
        }

        primaryRentToken.safeTransfer(_recipient, _withdrawAmount);
        totalRentValue -= _withdrawAmount;

        emit RentTransferred(_recipient, _withdrawAmount);
    }

    /**
     * @notice Internal method for claiming rent for a tokenId from the RentManager.
     * @param rentManager RentManager to claim rent from for token.
     * @param tokenId Token claiming rent for.
     * @return claimed -> Amount of rent claimed.
     */
    function _claimRentForToken(IRentManager rentManager, uint256 tokenId) internal returns (uint256 claimed) {
        uint256 preBal = primaryRentToken.balanceOf(address(this));
        rentManager.claimRentForToken(tokenId);
        claimed = primaryRentToken.balanceOf(address(this)) - preBal;
    }

    /**
     * @notice View method used to calculate amount of shares required given the usdValue of the TNFT and amount of rent needed.
     * @dev If primaryRentToken.decimals != 6, this func will fail.
     * @param usdValue USD value of token being quoted.
     */
    function _quoteShares(uint256 usdValue) internal view returns (uint256 shares) {
        uint256 ts = totalSupply();
        if (ts == 0) {
            shares = usdValue / 100; // set initial price -> $100
        } else {
            shares = ((usdValue * ts) / getTotalValueOfBasket());
        }
    }

    /**
     * @dev Get value of TNFT in native currency.
     * @param _tangibleNFT TNFT contract address of token.
     * @param _fingerprint fingerprint of token.
     * @return currency -> ISO code of native currency. (i.e. "GBP")
     * @return value -> Value of token in native currency.
     * @return decimals -> Amount of decimals used for precision.
     */
    function _getTnftNativeValue(address _tangibleNFT, uint256 _fingerprint) internal view returns (string memory currency, uint256 value, uint8 decimals) {
        (currency, value, decimals) = IBasketManager(basketManager).currencyCalculator().getTnftNativeValue(_tangibleNFT, _fingerprint);
    }


    /**
     * @notice This method is an internal view method that fetches the RentManager contract for a specified TNFT contract.
     * @param _tangibleNFT TNFT contract address we want the RentManager for.
     * @return RentManager contract reference.
     */
    function _getRentManager(address _tangibleNFT) internal view returns (IRentManager) {
        return IFactory(factory()).rentManager(ITangibleNFT(_tangibleNFT));
    }

    /**
     * @notice This method is an internal view method that fetches the PriceOracle contract for a specified TNFT contract.
     * @param _tangibleNFT TNFT contract address we want the PriceOracle for.
     * @return PriceOracle contract reference.
     */
    function _getOracle(address _tangibleNFT) internal view returns (IPriceOracle) {
        ITangiblePriceManager priceManager = IFactory(factory()).priceManager();
        return ITangiblePriceManager(address(priceManager)).oracleForCategory(ITangibleNFT(_tangibleNFT));
    }

    /**
     * @notice This method is an internal view method that fetches the RWAPriceNotificationDispatcher contract for a specified TNFT contract.
     * @param _tangibleNFT TNFT contract address we want the RWAPriceNotificationDispatcher for.
     */
    function _getNotificationDispatcher(address _tangibleNFT) internal returns (IRWAPriceNotificationDispatcher) {
        return IGetNotificationDispatcher(address(_getOracle(_tangibleNFT))).notificationDispatcher();
    }

    /**
     * @notice Internal method for returning the address of BasketsVrfConsumer contract.
     * @return Address of BasketsVrfConsumer.
     */
    function _getBasketVrfConsumer() internal view returns (address) {
        return IBasketManager(IFactory(factory()).basketsManager()).basketsVrfConsumer();
    }

    /**
     * @notice Internal method for returning the address of RevenueDistributor contract.
     * @return Address of RevenueDistributor.
     */
    function _getRevenueDistributor() internal view returns (address) {
        return IBasketManager(IFactory(factory()).basketsManager()).revenueDistributor();
    }

    /**
     * @notice This method returns whether a provided TNFT (category) address exists in the tnftsSupported array and if so, where in the array.
     * @param _tnft contract address.
     * @return index -> Where in the `tnftsSupported` array the specified contract address resides.
     * @return exists -> If address exists in `tnftsSupported`, will be true. Otherwise false.
     */
    function _isSupportedTnft(address _tnft) internal view returns (uint256 index, bool exists) {
        for (uint256 i; i < tnftsSupported.length; ++i) {
            if (tnftsSupported[i] == _tnft) return (i, true);
        }
        return (0, false);
    }
}