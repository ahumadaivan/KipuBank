// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title KipuBank V2
/// @author ahumadaivan
/// @notice It allows each user to deposit and withdraw ETH and USDC with a withdrawal cap and a global cap in usd.

//   _________________________
//  |                         |
//  |        LIBRARIES        |
//  |_________________________|

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


//   _________________________
//  |                         |
//  |       INTERFACES        |
//  |_________________________|

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract KipuBankV2 is Ownable, ReentrancyGuard  {

    //   _________________________
    //  |                         |
    //  |     TYPE DECLARATION    |
    //  |_________________________|
    using SafeERC20 for IERC20;

    //   _________________________
    //  |                         |
    //  |     STATE VARIABLES     |
    //  |_________________________|
    
    ///@notice inmutable variable to store USDC's address
    IERC20 immutable i_usdc;

    /// @notice address blacklist
    mapping (address => bool) public blacklist;

    /// @notice wei and usd balance for each account and each token (0 = wei)
    mapping (address => mapping(address => uint256)) private _balances;

    /// @notice deposit amount for each account and each token
    mapping (address => mapping(address => uint256)) private _deposits;

    /// @notice withdrawals amount for each account and each token
    mapping (address => mapping(address => uint256)) private _withdrawals;

    /// @notice bank's wei total
    uint256 private _totalWeiBank;
    /// @notice bank's usdc total
    uint256 private _totalUSDCBank;

    ///@notice constant variable to store the Data Feed heartbeat
    uint16 constant ORACLE_HEARTBEAT = 3600;
    ///@notice constant variable to store the decimal factor
    uint256 constant DECIMAL_FACTOR = 1 * 10 ** 20;

    /// @notice deposits and withdrawals counters
    uint64 public totalDeposits;
    uint64 public totalWithdrawals;

    /// @notice  withdrawals and usd bank limits
    uint256 public immutable i_withdrawCap;
    uint256 public immutable i_bankCap;

    ///@notice variable to store the Chainlink Feed's address 
    AggregatorV3Interface public s_feeds; //0x694AA1769357215DE4FAC081bf1f309aDC325306 Ethereum ETH/USD

    //   ___________________
    //  |                   |
    //  |       EVENTS      |
    //  |___________________|

    /// @notice Emitted when a successful withdrawal occurs
    /// @param receiver Address that received the withdrawal
    /// @param amount   Amount withdrawn (in wei or USDC units)
    event KipuBankV2_WithdrawalSuccess(address receiver, uint256 amount);

    /// @notice Emitted when a successful deposit occurs
    /// @param sender Address that made the deposit
    /// @param token  Token address (address(0) for ETH)
    /// @param amount Amount deposited (in wei or USDC units)
    event KipuBankV2_DepositSuccess(address sender, address token, uint256 amount);

    /// @notice Emitted when a user is added to the blacklist
    event KipuBankV2_AddedToBlacklist(address user);

    /// @notice Emitted when a user is removed from the blacklist
    event KipuBankV2_RemovedFromBlacklist(address user);

    /// @notice Emitted when the Chainlink feed address is updated
    event KipuBankV2_ChainlinkFeedUpdated(address newFeedAddress);

    //   ___________________
    //  |                   |
    //  |      ERRORS       |
    //  |___________________|

    /// @notice error emitido cuando el monto es 0
    error KipuBankV2_ZeroAmount();

    /// @notice error emitido cuando retiro supera el umbral limite
    /// @param attemptedUSD   Monto en usd que se intento retirar
    error KipuBankV2_WithdrawalExceedsLimit(uint256 attemptedUSD);

    /// @notice error emitido cuando el banco supero el limite global de depositos
    /// @param attemptedAmount   Monto en wei que se intento depositar
    error KipuBankV2_BankExceedsGlobalCap(uint256 attemptedAmount);

    /// @notice error emitido cuando una transacción nativa falla
    /// @param receiver       Address de quien quiso retirar.
    /// @param token        Token in which the withdrawal was attempted
    /// @param amount        Monto en wei que quiso retirar.
    error KipuBankV2_WithdrawalFailed(address receiver, address token, uint256 amount);

    /// @notice error emitido cuando una transacción falla por saldo insuficiente
    /// @param user       Address de quien quiso retirar.
    /// @param token        Token in which the withdrawal was attempted
    /// @param amount        Monto en wei que quiso retirar.
    error KipuBankV2_InsufficientBalance(address user, address token, uint256 amount);

    /// @notice parametros de inicializacion invalidos
    /// @param withdrawCap    Capacidad maxima de retiro del banco.
    /// @param bankCap      Capacidad maxima de wei del banco.
    error KipuBankV2_InvalidInitialization(uint256 withdrawCap, uint256 bankCap);

    /// @notice error emited when the user is blacklisted
    error KipuBankV2_BlacklistedUser();

    ///@notice error emitido cuando el retorno del oráculo es incorrecto
    error KipuBankV2_OracleCompromised();

    ///@notice error emitido cuando la última actualización del oráculo es mayor que el heartbeat
    error KipuBankV2_StalePrice();

    //   _____________________
    //  |                     |
    //  |      MODIFIERS      |
    //  |_____________________|


    /// @notice Verifies that the user has sufficient balance to perform the operation 
    /// @param _amount    Amount in wei
    modifier onlyDirectionsWithBalance(address _token, uint256 _amount) {
        if (_balances[msg.sender][_token] < _amount) revert KipuBankV2_InsufficientBalance(msg.sender, _token, _amount); 
        _;
    }

    /// @notice Verifies that the amount is higher than zero
    /// @param _amount    Amount in wei
    modifier nonZeroAmount(uint256 _amount) {
        if (_amount == 0) revert KipuBankV2_ZeroAmount();
        _;
    }

    /// @notice Verifies the sender is not blacklisted
    modifier onlyNotBlacklistedUsers() {
        if (blacklist[msg.sender]) revert KipuBankV2_BlacklistedUser();
        _;
    }

    //   _______________________
    //  |                       |
    //  |      CONSTRUCTOR      |
    //  |_______________________|


    /// @param _owner         initial owner
    /// @param _feed          address Chainlink Feed ETH/USD 
    /// @param _usdc          address USDC token
    /// @param _withdrawalCapUsd  withdrawal cap in USD (6 dec)
    /// @param _bankCapUsd    global cap in USD (6 dec)
    constructor(address _owner, address _feed, address _usdc, uint256 _withdrawalCapUsd, uint256 _bankCapUsd) Ownable(_owner) {
        if (_bankCapUsd == 0 || _withdrawalCapUsd == 0 || _bankCapUsd < _withdrawalCapUsd) {
            revert KipuBankV2_InvalidInitialization(_withdrawalCapUsd, _bankCapUsd);
        }
        i_bankCap = _bankCapUsd;
        i_withdrawCap = _withdrawalCapUsd;
        s_feeds = AggregatorV3Interface(_feed);
        i_usdc = IERC20(_usdc);
    }

    //   _____________________
    //  |                     |
    //  |      FUNCTIONS      |
    //  |_____________________|

    // RECEIVE y FALLBACK


    receive() external payable nonReentrant {
        _depositETH(msg.sender, msg.value);
    }

    fallback() external payable nonReentrant{
        if (msg.value == 0) revert KipuBankV2_ZeroAmount();
        _depositETH(msg.sender, msg.value);
    }

    // EXTERNAL 

    /// @notice Withdraw ETH from the user's vault
    /// @param _weiAmount Amount to withdraw in wei
    function withdrawETH(uint256 _weiAmount) external 
        nonReentrant
        onlyNotBlacklistedUsers
        nonZeroAmount(_weiAmount)  
        onlyDirectionsWithBalance(address(0), _weiAmount)  
    { 
        // Check 
        uint256 _amountUSD = _convertEthToUSD(_weiAmount);
        if (_amountUSD > i_withdrawCap) revert KipuBankV2_WithdrawalExceedsLimit(_amountUSD); 
        
        // Effects 
        _balances[msg.sender][address(0)] -= _weiAmount;
        _totalWeiBank -= _weiAmount; 
        _withdrawals[msg.sender][address(0)]++; 
        totalWithdrawals++; 
        
        // Interaction 
        _withdrawETH(msg.sender, _weiAmount); 
        
        emit KipuBankV2_WithdrawalSuccess(msg.sender, _weiAmount); 
    } 
    
    /// @notice Withdraw USDC from the user's vault
    /// @param _usdcAmount Amount to withdraw in USDC units
    function withdrawUSDC(uint256 _usdcAmount) external
        nonReentrant 
        onlyNotBlacklistedUsers  
        nonZeroAmount(_usdcAmount)
        onlyDirectionsWithBalance(address(i_usdc), _usdcAmount) 
        { 
        // Check 
        if (_usdcAmount > i_withdrawCap) revert KipuBankV2_WithdrawalExceedsLimit(_usdcAmount); 
        // Effects 
        _balances[msg.sender][address(i_usdc)] -= _usdcAmount; 
        _totalUSDCBank -= _usdcAmount; 
        _withdrawals[msg.sender][address(i_usdc)]++; 
        totalWithdrawals++; 
        
        // Interaction 
        i_usdc.safeTransfer(msg.sender, _usdcAmount);
        emit KipuBankV2_WithdrawalSuccess(msg.sender, _usdcAmount); 
    }
    
    /// @notice external deposit ETH
    function depositETH() external payable
        nonReentrant 
    {
        _depositETH(msg.sender, msg.value);
    }

    /// @dev USDC deposit 
    /// @param _usdcAmount   USDC amount received.
    function depositUSDC(uint256 _usdcAmount) public
        nonReentrant 
        nonZeroAmount(_usdcAmount)
    {        
        uint256 _total = _totalUSDCBank + _usdcAmount + _convertEthToUSD(_totalWeiBank);
        if(_total > i_bankCap) revert KipuBankV2_BankExceedsGlobalCap(_total);

        // Effects
        _totalUSDCBank += _usdcAmount;
        _balances[msg.sender][address(i_usdc)] += _usdcAmount;
        _deposits[msg.sender][address(i_usdc)]++;
        totalDeposits++;

        // Interactions
        i_usdc.safeTransferFrom(msg.sender, address(this), _usdcAmount);

        emit KipuBankV2_DepositSuccess(msg.sender, address(i_usdc), _usdcAmount);
    }

    /// @notice View current ETH balance (in wei)
    /// @return balance    Wei Balance.
    function getEthBalance() external view returns(uint256 balance){
        return _balances[msg.sender][address(0)];
    }

    /// @notice View current USDC balance (in USDC units)
    /// @return balance    USDC balance
    function getUsdcBalance() external view returns(uint256 balance){
        return _balances[msg.sender][address(i_usdc)];
    }

    /// @notice View total USD balance (ETH converted to USD + USDC)
    /// @return balance    USD balance
    function getTotalUsdBalance() external view returns(uint256 balance){
        uint256 _total = _balances[msg.sender][address(0)];
        uint256 _totalUSD = _convertEthToUSD(_total) + _balances[msg.sender][address(i_usdc)];
        return _totalUSD;
    }

    // RESTRICTED FOR OWNER

    /// @notice Add user to the blacklist
    /// @param _user Address to be added to the blacklist
    function addToBlacklist(address _user) external onlyOwner {
        blacklist[_user] = true;
        emit KipuBankV2_AddedToBlacklist(_user);
    }

    /// @notice Add user to the blacklist
    /// @param _user Address to be added to the blacklist
    function removeFromBlacklist(address _user) external onlyOwner {
        blacklist[_user] = false;
        emit KipuBankV2_RemovedFromBlacklist(_user);
    }

    /**
     * @notice Change ETH/USD Chainlink Feed
     * @param _feed new Price Feed's address
     */
    function setFeeds(address _feed) external onlyOwner {
        s_feeds = AggregatorV3Interface(_feed);

        emit KipuBankV2_ChainlinkFeedUpdated(_feed);
    }

    // PRIVATE 

    /**
    * @notice Returns the latest ETH/USD price from Chainlink
    * @return ethUSDPrice_ ETH/USD price from Oracle
    */
    function chainlinkFeed() internal view returns (uint256 ethUSDPrice_) {
        (, int256 price,, uint256 updatedAt,) = s_feeds.latestRoundData();

        if (price <= 0) revert KipuBankV2_OracleCompromised();
        if (block.timestamp - updatedAt > ORACLE_HEARTBEAT) revert KipuBankV2_StalePrice();

        ethUSDPrice_ = uint256(price);
    }

    /// @notice Converts ETH amount (in wei) to USD (6 decimals)
    // @param _ethAmountWei     ETH amount to convert
    // @return convertedAmount_ USD result

    function _convertEthToUSD(uint256 _ethAmountWei) internal view returns (uint256 convertedAmount_) {              
        convertedAmount_ = (_ethAmountWei * chainlinkFeed()) / DECIMAL_FACTOR;
    }

    /// @dev Safe native ETH transfer
    function _withdrawETH(address _receiver, uint256 _weiAmount) private  {
        (bool exito, ) = _receiver.call{value: _weiAmount}("");
        if(!exito) revert KipuBankV2_WithdrawalFailed(_receiver, address(0), _weiAmount);
    }

    /// @dev Shared ETH deposit logic. Validates global cap and updates balances.
    /// @param _sender     Direction that's depositing
    /// @param _weiAmount   Amount in wei
    function _depositETH(address _sender, uint256 _weiAmount) private 
        nonZeroAmount(_weiAmount)
    {   
        // Checks
        uint256 _total = _totalUSDCBank + _convertEthToUSD(_totalWeiBank + _weiAmount);
        if(_total > i_bankCap) revert KipuBankV2_BankExceedsGlobalCap(_total);

        // Effects
        _totalWeiBank += _weiAmount;
        _balances[_sender][address(0)] += _weiAmount;
        _deposits[_sender][address(0)]++;
        totalDeposits++;

        emit KipuBankV2_DepositSuccess(_sender, address(0), _weiAmount);
    }


}