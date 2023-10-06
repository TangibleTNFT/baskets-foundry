// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// chainlink imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// tangible imports
import { ITangibleNFT, ITangibleNFTExt } from "@tangible/interfaces/ITangibleNFT.sol";
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { IRentManager, IRentManagerExt } from "@tangible/interfaces/IRentManager.sol";

// local imports
import { IBasket } from "./interfaces/IBasket.sol";
import { IBasketManager } from "./interfaces/IBasketsManager.sol";
import { IBasketsVrfConsumer } from "./interfaces/IBasketsVrfConsumer.sol";

// TODO: How to handle total value? TBA

/**
 * @title Basket
 * @author Chase Brown
 * @notice ERC-20 token that represents a basket of ERC-721 TangibleNFTs that are categorized into "baskets".
 */
contract Basket is Initializable, ERC20Upgradeable, IBasket, FactoryModifiers, ReentrancyGuardUpgradeable {

    // ~ State Variables ~

    TokenData[] public depositedTnfts;

    //RedeemData[] internal tokensInBudget; // Note: Only used during runtime. Otherwise empty

    address[] public tnftsSupported;

    mapping(address => uint256[]) public tokenIdLibrary;

    mapping(address => mapping(uint256 => uint256)) public valueTracker; // tracks USD value of TNFT

    /// @notice TangibleNFT contract => tokenId => if deposited into address(this).
    mapping(address => mapping(uint256 => bool)) public tokenDeposited;

    mapping(uint256 => bool) public featureSupported;

    uint256[] public supportedFeatures;

    string[] public supportedCurrency; // TODO: Revisit -> https://github.com/TangibleTNFT/usdr/blob/master/contracts/TreasuryTracker.sol

    uint256 public tnftType;

    uint256 public totalNftValue; // NOTE: For testing. Will be replaced

    mapping(uint256 => RedeemRequest) public redeemRequestInFlightData;

    mapping(address => bool) public redeemerHasRequestInFlight;

    IERC20Metadata public primaryRentToken; // USDC by default

    address public deployer;


    // ~ Events ~

    /**
     * @notice This event is emitted when a TNFT is deposited into this basket.
     * @param prevOwner Previous owner before deposit. Aka depositor.
     * @param tnft TNFT contract address of token being deposited.
     * @param tokenId TokenId identifier of token being deposited.
     */
    event TNFTDeposited(address prevOwner, address indexed tnft, uint256 indexed tokenId);

    /**
     * @notice This event is emitted when a TNFT random redeem has been requested and is "in flight".
     * @param redeemer Address of redeemer.
     * @param budget Budget of basket tokens redeemer wishes to work with.
     */
    event RedeemRequestInFlight(address redeemer, uint256 budget);

    /**
     * @notice This event is emitted when a TNFT is redeemed from this basket.
     * @param newOwner New owner before deposit. Aka redeemer.
     * @param tnft TNFT contract address of token being redeemed.
     * @param tokenId TokenId identifier of token being redeemed.
     */
    event TNFTRedeemed(address newOwner, address indexed tnft, uint256 indexed tokenId);

    // TODO: FOR TESTING ONLY
    event Debug(string, uint256);

    
    // ~ Modifiers ~

    /// @notice This modifier is to verify msg.sender is the BasketVrfConsumer constract.
    modifier onlyBasketVrfConsumer() {
        require(msg.sender == _getBasketVrfConsumer());
        _;
    }


    // ~ Constructor ~

    constructor() FactoryModifiers(address(0)) {
        _disableInitializers();
    }


    // ~ Initializer ~

    /**
     * @notice Initializes Basket contract.
     * @param _name Unique name of basket contract.
     * @param _symbol Unique symbol of basket contract.
     * @param _factoryProvider FactoryProvider contract address.
     * @param _tnftType TNFT Type (category).
     * @param _rentToken ERC-20 token being used for rent. USDC by default.
     * @param _features Array of features TNFTs must support to be in this basket.
     * @param _deployer Address of creator of the basket contract.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _factoryProvider,
        uint256 _tnftType,
        address _rentToken,
        uint256[] memory _features,
        address _deployer
    ) external initializer {   
        require(_factoryProvider != address(0), "FactoryProvider == address(0)");
        
        // If _features is not empty, add features
        if (_features.length > 0) {
            for (uint256 i; i < _features.length;) {
                supportedFeatures.push(_features[i]);
                featureSupported[_features[i]] = true;

                unchecked {
                    ++i;
                }
            }
        }

        __ERC20_init(_name, _symbol);
        __FactoryModifiers_init(_factoryProvider);

        tnftType = _tnftType;
        deployer = _deployer;

        primaryRentToken = IERC20Metadata(_rentToken);
    }

    
    // ~ External Functions ~

    /**
     * @notice This method allows a user to deposit a batch of TNFTs into the basket.
     * @dev Gas block limit is reached at 90 ~ 100 tokens.
     */
    function batchDepositTNFT(address[] memory _tangibleNFTs, uint256[] memory _tokenIds) external returns (uint256[] memory basketShares) {
        uint256 length = _tangibleNFTs.length;
        require(length == _tokenIds.length, "Arrays not same size");

        basketShares = new uint256[](length);

        for (uint256 i; i < length;) {
            basketShares[i] = _depositTNFT(_tangibleNFTs[i], _tokenIds[i], msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method allows a user to deposit their TNFT in exchange for Basket tokens.
     */
    function depositTNFT(address _tangibleNFT, uint256 _tokenId) external returns (uint256 basketShare) {
        basketShare = _depositTNFT(_tangibleNFT, _tokenId, msg.sender);
    }

    /**
     * @notice This internal method is used to deposit a specified TNFT from a depositor address to this basket.
     *         The deposit will be minted a sufficient amount of basket tokens in return.
     */
    function _depositTNFT(address _tangibleNFT, uint256 _tokenId, address _depositor) internal returns (uint256 basketShare) {
        require(!tokenDeposited[_tangibleNFT][_tokenId], "Token already deposited");
        // if contract supports features, make sure tokenId has a supported feature
        require(_isCompatibleTnft(_tangibleNFT, _tokenId), "Token incompatible");

        // get token fingerprint
        uint256 fingerprint = ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId);

        // calculate usd value of TNFT with 18 decimals
        uint256 usdValue = _getUSDValue(_tangibleNFT, _tokenId);
        require(usdValue > 0, "Unsupported TNFT");

        // update contract
        tokenDeposited[_tangibleNFT][_tokenId] = true;
        valueTracker[_tangibleNFT][_tokenId] = usdValue;

        depositedTnfts.push(TokenData(_tangibleNFT, _tokenId, fingerprint));
        tokenIdLibrary[_tangibleNFT].push(_tokenId);

        (, bool exists) = _isSupportedTnft(_tangibleNFT);
        if (!exists) {
            tnftsSupported.push(_tangibleNFT);
        }

        // take token from depositor
        IERC721(_tangibleNFT).safeTransferFrom(msg.sender, address(this), _tokenId);

        // Claim rent from tnft::rentManager and keep it in this contract TODO TEST
        uint256 preBal = primaryRentToken.balanceOf(address(this));

        // claim rent for TNFT being redeemed.
        uint256 receivedRent;
        IRentManager rentManager = _getRentManager(_tangibleNFT);

        if (rentManager.claimableRentForToken(_tokenId) > 0) {
            receivedRent += rentManager.claimRentForToken(_tokenId);
        }

        // verify claimed balance
        require(primaryRentToken.balanceOf(address(this)) == (preBal + receivedRent), "claiming error");

        // calculate shares for depositor
        basketShare = _quoteShares(usdValue, receivedRent);

        // if msg.sender is basketManager, it's making an initial deposit -> receiver of basket tokens needs to be deployer.
        if (msg.sender == IFactory(IFactoryProvider(factoryProvider).factory()).basketsManager()) {
            _depositor = deployer;
        }

        // mint basket tokens to user
        _mint(_depositor, basketShare);

        // Update total nft value in this contract
        totalNftValue += usdValue;

        emit TNFTDeposited(_depositor, _tangibleNFT, _tokenId);
    }

    /**
     * @notice This method allows a user to redeem a TNFT in exchange for their Basket tokens. // NOTE: For testing only?
     */
    function redeemTNFT(address _tangibleNFT, uint256 _tokenId, uint256 _amountBasketTokens) external {

        // get usd value of TNFT token being redeemed.
        uint256 usdValue = valueTracker[_tangibleNFT][_tokenId];
        require(usdValue > 0, "Unsupported TNFT");

        // Calculate amount of rent to send to redeemer.
        uint256 amountRent = (usdValue * (_getRentBal() / 10**12)) / totalNftValue;

        // Get shares required
        uint256 sharesRequired = _quoteShares(usdValue, amountRent);

        // Verify the user has sufficient amount of tokens.
        require(_amountBasketTokens >= sharesRequired, "Insufficient offer");
        if (_amountBasketTokens > sharesRequired) _amountBasketTokens = sharesRequired;

        _redeemTNFT(msg.sender, _tangibleNFT, _tokenId, usdValue, amountRent, _amountBasketTokens);
    }

    /**
     * @notice This method is used to fetch a random number to then receive a random TNFT.
     */
    function redeemRandomTNFT(uint256 _budget) external returns (uint256 requestId) {
        address redeemer = msg.sender;
        require(!redeemerHasRequestInFlight[redeemer], "redeem request in progress");
        require(balanceOf(redeemer) >= _budget, "Insufficient balance");

        (,, bool validBudget) = checkBudget(_budget); // TODO: Remove from this function -> call before redeemRandomTNFT
        require(validBudget, "Insufficient budget");

        requestId = IBasketsVrfConsumer(_getBasketVrfConsumer()).makeRequestForRandomWords();

        redeemRequestInFlightData[requestId] = RedeemRequest(redeemer, _budget);
        redeemerHasRequestInFlight[redeemer] = true;

        emit RedeemRequestInFlight(redeemer, _budget);
    }

    /**
     * @notice This method is the vrf callback method. Will use the random seed to choose a random TNFT for redeemer.
     */
    function fulfillRandomRedeem(uint256 requestId, uint256 randomWord) external onlyBasketVrfConsumer {
        address redeemer = redeemRequestInFlightData[requestId].redeemer;
        uint256 budget = redeemRequestInFlightData[requestId].budget;

        redeemerHasRequestInFlight[redeemer] = false;
        delete redeemRequestInFlightData[requestId];

        // a. Create an array of TNFTs within budget
        (RedeemData[] memory tokensInBudget,,) = checkBudget(budget);

        uint256 len = tokensInBudget.length;
        require(len > 0, "0");

        // b. use randomWord to shuffle array
        for (uint256 i; i < len;) {
            uint256 key = i + (randomWord % (len - i));

            if (i != key) {
                RedeemData memory temp = tokensInBudget[key];
                tokensInBudget[key] = tokensInBudget[i];
                tokensInBudget[i] = temp;
            }

            unchecked {
                ++i;
            }
        }

        // c. redeem NFT in index 0
        _redeemTNFT(
            redeemer,
            tokensInBudget[0].tnft,
            tokensInBudget[0].tokenId,
            tokensInBudget[0].usdValue,
            tokensInBudget[0].amountRent,
            tokensInBudget[0].sharesRequired
        );
    }

    /**
     * @notice Internal method for redeeming a specified TNFT in the basket
     */
    function _redeemTNFT(
        address _redeemer,
        address _tangibleNFT,
        uint256 _tokenId,
        uint256 _usdValue,
        uint256 _amountRent,
        uint256 _amountBasketTokens
    ) internal nonReentrant {
        require(balanceOf(_redeemer) >= _amountBasketTokens, "Insufficient balance");
        require(tokenDeposited[_tangibleNFT][_tokenId], "Invalid token");

        // update contract
        tokenDeposited[_tangibleNFT][_tokenId] = false;

        uint256 index;
        (index,) = _isDepositedTnft(_tangibleNFT, _tokenId);
        depositedTnfts[index] = depositedTnfts[depositedTnfts.length - 1];
        depositedTnfts.pop();

        (index,) = _isTokenIdLibrary(_tangibleNFT, _tokenId);
        tokenIdLibrary[_tangibleNFT][index] = tokenIdLibrary[_tangibleNFT][tokenIdLibrary[_tangibleNFT].length - 1];
        tokenIdLibrary[_tangibleNFT].pop();

        if (tokenIdLibrary[_tangibleNFT].length == 0) {
            (index,) = _isSupportedTnft(_tangibleNFT); 
            tnftsSupported[index] = tnftsSupported[tnftsSupported.length - 1];
            tnftsSupported.pop();
        }

        // Send rent to redeemer
        if (_amountRent > 0) {

            // If there's sufficient rent sitting in the basket, no need to claim, otherwise claim rent from manager first.
            primaryRentToken.balanceOf(address(this)) >= _amountRent ?
                assert(primaryRentToken.transfer(_redeemer, _amountRent)) :
                _redeemRent(_tangibleNFT, _tokenId, _amountRent, _redeemer);
        }

        // Transfer tokenId to user
        IERC721(_tangibleNFT).safeTransferFrom(address(this), _redeemer, _tokenId);

        totalNftValue -= _usdValue;
        _burn(_redeemer, _amountBasketTokens);

        emit TNFTRedeemed(_redeemer, _tangibleNFT, _tokenId);
    }

    /**
     * @notice This view method returns true if a specified token contains the features needed to be deposited into this basket.
     */
    function isCompatibleTnft(address _tangibleNFT, uint256 _tokenId) external view returns (bool) { // TODO: Remove public
        return _isCompatibleTnft(_tangibleNFT, _tokenId);
    }

    /**
     * @notice This method returns the unclaimed rent balance of all TNFTs inside the basket.
     * @dev Returns an amount in USD (stablecoin) with 18 decimal points.
     */
    function getRentBal() external view returns (uint256 totalRent) {
        return _getRentBal();
    }

    function getQuoteIn(address _tangibleNFT, uint256 _tokenId) external view returns (uint256 shares) {
        return _getQuoteIn(_tangibleNFT, _tokenId);
    }

    function getQuoteOut(address _tangibleNFT, uint256 _tokenId) external view returns (uint256 sharesRequired) {
        return _getQuoteOut(_tangibleNFT, _tokenId);
    }

    /**
     * @notice Allows address(this) to receive ERC721 tokens.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function getDepositedTnfts() external view returns (TokenData[] memory) {
        return depositedTnfts;
    }

    function getTnftsSupported() external view returns (address[] memory) {
        return tnftsSupported;
    }

    function getTokenIdLibrary(address _tnft) external view returns (uint256[] memory) {
        return tokenIdLibrary[_tnft];
    }

    function getSupportedFeatures() external view returns (uint256[] memory) {
        return supportedFeatures;
    }

    
    // ~ Public Functions ~

    /**
     * @notice This function returns a list of TNFTs that could be potentially redeemed for a budget of basket tokens.
     * @dev This should be called by the front end prior to allowing any user from executing redeemRandomTNFT to ensure
     *      when a callback occurs from vrf, it wasn't wasted fees to find the budget is not eligible for any redeemable TNFTs.
     */
    function checkBudget(uint256 _budget) public view returns (RedeemData[] memory inBudget, uint256 quantity, bool valid) { // TODO: Optimize
        uint256 len = depositedTnfts.length;
        inBudget = new RedeemData[](len);

        uint256 rentBal = _getRentBal() / 10**12;
        uint256 totalNftVal = totalNftValue;

        for (uint256 i; i < len;) {

            // get usd value of TNFT token
            uint256 usdValue = valueTracker[depositedTnfts[i].tnft][depositedTnfts[i].tokenId];
            // Calculate amount of rent that would be received
            uint256 amountRent = (usdValue * rentBal) / totalNftVal;
            // Calculate amount of basket tokens needed. Usd value of NFT + rent amount / share price == total basket tokens.
            uint256 sharesRequired = _quoteShares(usdValue, amountRent);

            if (_budget >= sharesRequired) {
                inBudget[quantity] = 
                    RedeemData(
                        depositedTnfts[i].tnft,
                        depositedTnfts[i].tokenId,
                        usdValue,
                        amountRent,
                        sharesRequired
                    );
                unchecked {
                    ++quantity;
                }
            }

            unchecked {
                ++i;
            }
        }

        quantity > 0 ? valid = true : valid = false;
    }

    /**
     * @notice Return the USD value of share token for underlying assets, 18 decimals
     * @dev Underyling assets = TNFT + Accrued revenue
     */
    function getSharePrice() public view returns (uint256 sharePrice) { // TODO: Remove?
        if (totalSupply() == 0) {
            // initial share price is $1
            return 1e18;
        }
        // Total value of collateral assets on basket, in 18 decimals
        uint256 collateralValue = getTotalValueOfBasket();

        sharePrice = (collateralValue * 10 ** decimals()) / totalSupply();

        require(sharePrice != 0, "share is 0");
    }

    function getTotalValueOfBasket() public view returns (uint256 totalValue) {
        // Get value of each TNFTs by currency
        // for (uint256 i; i < supportedCurrency.length;) {
        //     totalValue += _getUSDValue(supportedCurrency[i], currencyBalance[supportedCurrency[i]], 18);
        //     unchecked {
        //         ++i;
        //     }
        // }
        totalValue += totalNftValue;

        // get value of rent accrued by this contract
        totalValue += _getRentBal();
    }

    
    // ~ Internal Functions ~

    function _getQuoteIn(address _tangibleNFT, uint256 _tokenId) internal view returns (uint256 shares) { // TODO: move off chain
        // calculate usd value of TNFT with 18 decimals
        uint256 usdValue = _getUSDValue(_tangibleNFT, _tokenId);
        require(usdValue > 0, "Unsupported TNFT");
        
        // get rent amount claimable
        IRentManager rentManager = _getRentManager(_tangibleNFT);
        uint256 claimableRent = rentManager.claimableRentForToken(_tokenId);

        // calculate shares for depositor
        shares = _quoteShares(usdValue, claimableRent);
    }

    function _getQuoteOut(address _tangibleNFT, uint256 _tokenId) internal view returns (uint256 sharesRequired) { // TODO: move off chain
        // fetch usd value of tnft
        uint256 usdValue = valueTracker[_tangibleNFT][_tokenId];
        require(usdValue > 0, "Unsupported TNFT");
        
        // get get rent amount
        uint256 amountRent = (usdValue * (_getRentBal() / 10**12)) / totalNftValue;

        // Get shares required
        sharesRequired = _quoteShares(usdValue, amountRent);
    }

    /**
     * @notice This method returns the unclaimed rent balance of all TNFTs inside the basket.
     * @dev Returns an amount in USD (stablecoin) with 18 decimal points.
     */
    function _getRentBal() internal view returns (uint256 totalRent) { // TODO: Optimize
        uint256 decimals = decimals() - IERC20Metadata(primaryRentToken).decimals();

        // iterate through all supported tnfts and tokenIds deposited for each tnft. // TODO: Test when tnftsSupported.length > 1.
        for (uint256 i; i < tnftsSupported.length;) {
            address tnft = tnftsSupported[i];

            uint256[] memory claimables = _getRentManager(tnft).claimableRentForTokenBatch(tokenIdLibrary[tnft]); // TODO: Get total

            for (uint256 j; j < claimables.length;) {
                if (claimables[j] > 0) {
                    decimals > 0 ?
                        totalRent += claimables[j] * 10**decimals :
                        totalRent += claimables[j];
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        decimals > 0 ?
            totalRent += primaryRentToken.balanceOf(address(this)) * 10**decimals :
            totalRent += primaryRentToken.balanceOf(address(this));
    }

    /**
     * @notice View method used to calculate amount of shares required given the usdValue of the TNFT and amount of rent needed.
     * @dev If primaryRentToken.decimals == 18, this func will fail.
     */
    function _quoteShares(uint256 usdValue, uint256 amountRent) internal view returns (uint256 shares) {
        uint256 combinedValue = (usdValue + (amountRent * 10**12));

        if (totalSupply() == 0) {
            shares = combinedValue;
        } else {
            shares = ((combinedValue * totalSupply()) / getTotalValueOfBasket());
        }
    }

    /**
     * @notice This internal method claims rent from the Rent Manager and transfers a specified amount to redeemer.
     */
    function _redeemRent(address _tnft, uint256 _tokenId, uint256 _amount, address _redeemer) internal { // TODO: Needs stress testing -> 1000+ NFTs // TODO: Optimize

        // TODO:
        // 1. Claim from USDC balance
        // 2. Claim from TNFT rent being redeemed
        // 3. Claim from other TNFTs in basket -> best method for this:
        //      a. sort array -> too comlpex, would need to build a single array of type (uint) and we'd lose which token IDs were in which TNFT contract.
        //                       Unless we wrote a custom sort method in this contract.
        //      b. Loop through main array, find largest claimable, claim that -> implemented.
        //      c. Iterate through main array from beginning to end until sufficient rent is claimed, save index until next redeem TODO: Try this

        // fetch current balance of USDC in this contract
        uint256 preBal = primaryRentToken.balanceOf(address(this));

        // first, claim rent for TNFT being redeemed.
        uint256 received = _getRentManager(_tnft).claimRentForToken(_tokenId);

        // verify claimed balance
        require(primaryRentToken.balanceOf(address(this)) == (preBal + received), "claiming error");

        // if we still need more rent, start claiming rent from TNFTs in basket.
        if (_amount > primaryRentToken.balanceOf(address(this))) {

            // declare master array to store all claimable rent data.
            RentData[] memory claimableRent = new RentData[](depositedTnfts.length);
            uint256 counter;

            // iterate through all TNFT contracts supported by this basket.
            for (uint256 i; i < tnftsSupported.length;) {
                address tnft = tnftsSupported[i];

                // for each TNFT supported, make a batch call to the rent manager for all rent claimable for the array of tokenIds.
                uint256[] memory claimables = _getRentManager(tnft).claimableRentForTokenBatch(tokenIdLibrary[tnft]);

                // iterate through the array of claimable rent for each tokenId for each TNFT and push it to the master claimableRent array.
                for (uint256 j; j < claimables.length;) {
                    claimableRent[counter] = RentData(tnft, tokenIdLibrary[tnft][j], claimables[j]); // TODO: Verify claimables[x] == correct tokenId at tokenIdLibrary[tnft][x]
                    unchecked {
                        ++counter;
                        ++j;
                    }
                }
                unchecked {
                    ++i;
                }
            }

            // we now iterate through the master claimable rent array, find the largest amount claimable, claim, then check if we need more
            while (_amount > primaryRentToken.balanceOf(address(this))) {
                uint256 mostValuableIndex;
                for (uint256 i; i < claimableRent.length;) {  // TODO: Refactor -> finding largest claimable multiple times can get expensive.
                    if (claimableRent[i].amountClaimable > claimableRent[mostValuableIndex].amountClaimable) {
                        mostValuableIndex = i;
                    }
                    unchecked {
                        ++i;
                    }
                }
                //rentManager = IFactory(IFactoryProvider(factoryProvider).factory()).rentManager(ITangibleNFT(claimableRent[mostValuableIndex].tnft));
                preBal = primaryRentToken.balanceOf(address(this));

                received = _getRentManager(claimableRent[mostValuableIndex].tnft).claimRentForToken(claimableRent[mostValuableIndex].tokenId);
                require(primaryRentToken.balanceOf(address(this)) == (preBal + received), "claiming error");
            }

        }

        // send rent to redeemer
        assert(primaryRentToken.transfer(_redeemer, _amount));
    }

    /**
     * @notice This view method returns true if a specified token contains the features needed to be deposited into this basket.
     */
    function _isCompatibleTnft(address _tangibleNFT, uint256 _tokenId) internal view returns (bool) {
        if (ITangibleNFTExt(_tangibleNFT).tnftType() != tnftType) return false;

        uint256 length = supportedFeatures.length;
        if(length > 0) {
            for (uint256 i; i < length;) {

                ITangibleNFT.FeatureInfo memory featureData = ITangibleNFTExt(_tangibleNFT).tokenFeatureAdded(_tokenId, supportedFeatures[i]);
                if (!featureData.added) return false;

                unchecked {
                    ++i;
                }
            }
        }

        return true;
    }

    /**
     * @dev Get value of TNFT in native currency TODO: Maybe put this code into a separate contract?
     */
    function _getTnftNativeValue(address _tangibleNFT, uint256 _fingerprint) internal view returns (string memory currency, uint256 value, uint8 decimals) {
        address factory = IFactoryProvider(factoryProvider).factory();

        ITangiblePriceManager priceManager = IFactory(factory).priceManager();
        IPriceOracle oracle = ITangiblePriceManager(address(priceManager)).oracleForCategory(ITangibleNFT(_tangibleNFT));

        uint256 currencyNum;
        (value, currencyNum) = oracle.marketPriceNativeCurrency(_fingerprint);

        ICurrencyFeedV2 currencyFeed = ICurrencyFeedV2(IFactory(IFactoryProvider(factoryProvider).factory()).currencyFeed());
        currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));

        decimals = oracle.decimals();
    }

    /**
     * @dev Get USD Value of given currency and amount, base 1e18
     */
    function _getUSDValue(address _tangibleNFT, uint256 _tokenId) internal view returns (uint256) {
        (string memory currency, uint256 amount, uint8 nativeDecimals) = _getTnftNativeValue(
            _tangibleNFT, ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId)
        );
        (uint256 price, uint256 priceDecimals) = _getUsdExchangeRate(currency);
        return (price * amount * 10 ** 18) / 10 ** priceDecimals / 10 ** nativeDecimals;
    }

    /**
     * @dev Get USD Price of given currency from ChainLink
     */
    function _getUsdExchangeRate(string memory _currency) internal view returns (uint256, uint256) {
        ICurrencyFeedV2 currencyFeed = ICurrencyFeedV2(IFactory(IFactoryProvider(factoryProvider).factory()).currencyFeed());
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(_currency);
        
        (, int256 price, , , ) = priceFeed.latestRoundData();
        if (price < 0) price = 0;

        return (uint256(price), priceFeed.decimals());
    }

    function _getBasketVrfConsumer() internal returns (address) {
        return IBasketManager(IFactory(IFactoryProvider(factoryProvider).factory()).basketsManager()).basketsVrfConsumer();
    }

    function _getRentManager(address _tangibleNFT) internal view returns (IRentManager) {
        return IFactory(IFactoryProvider(factoryProvider).factory()).rentManager(ITangibleNFT(_tangibleNFT));
    }

    /**
     * @notice This method returns whether a provided TNFT token exists in the depositedTnfts array and if so, where in the array.
     */
    function _isDepositedTnft(address _tnft, uint256 _tokenId) internal view returns (uint256 index, bool exists) {
        for(uint256 i; i < depositedTnfts.length;) {
            if (depositedTnfts[i].tokenId == _tokenId && depositedTnfts[i].tnft == _tnft) return (i, true);
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }

    /**
     * @notice This method returns whether a provided TNFT (category) address exists in the tnftsSupported array and if so, where in the array.
     */
    function _isSupportedTnft(address _tnft) internal view returns (uint256 index, bool exists) {
        for(uint256 i; i < tnftsSupported.length;) {
            if (tnftsSupported[i] == _tnft) return (i, true);
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }

    /**
     * @notice This method returns whether a provided tokenId exists in the tokenIdLibrary mapped array and if so, where in the array.
     */
    function _isTokenIdLibrary(address _tnft, uint256 _tokenId) internal view returns (uint256 index, bool exists) {
        for(uint256 i; i < tokenIdLibrary[_tnft].length;) {
            if (tokenIdLibrary[_tnft][i] == _tokenId) return (i, true);
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }
}
