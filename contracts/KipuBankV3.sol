// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title KipuBank V3
/// @author ahumadaivan
/// @notice It allows each user to deposit and withdraw ETH and any ERC-20 token supported by uniswap v2 swapping it for usdc
/// @notice with a withdrawal cap and a global cap in usdc.

//  _________________________
// |                         |
// |         LIBRARIES       |
// |_________________________|

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

//  _________________________
// |                         |
// |        INTERFACES       |
// |_________________________|

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02} from '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract KipuBankV3 is Ownable, ReentrancyGuard {

    //  _________________________
    // |                         |
    // |    TYPE DECLARATION     |
    // |_________________________|
    using SafeERC20 for IERC20;

    //  _________________________
    // |                         |
    // |     STATE VARIABLES     |
    // |_________________________|
    
    ///@notice inmutable variable to store USDC's address
    IERC20 immutable i_usdc;
    
    ///@notice uniswap router
    IUniswapV2Router02 public s_router;
    address public s_weth;

    /// @notice address blacklist
    mapping (address => bool) public blacklist;

    /// @notice wei and usd balance for each account and each token (0 = wei)
    mapping (address => mapping(address => uint256)) private _balances;

    /// @notice deposit amount for each account and each token
    mapping (address => mapping(address => uint256)) private _deposits;

    /// @notice withdrawals amount for each account and each token
    mapping (address => mapping(address => uint256)) private _withdrawals;

    /// @notice bank's usdc total
    uint256 private _totalUSDCBank;

    /// @notice deposits and withdrawals counters
    uint64 public totalDeposits;
    uint64 public totalWithdrawals;

    /// @notice  withdrawals and usd bank limits
    uint256 public immutable i_withdrawCap;
    uint256 public immutable i_bankCap;

    //  ___________________
    // |                   |
    // |       EVENTS      |
    // |___________________|

    /// @notice Emitted when a successful withdrawal occurs
    /// @param receiver Address that received the withdrawal
    /// @param amount   Amount withdrawn (in wei or USDC units)
    event KipuBankV3_WithdrawalSuccess(address receiver, uint256 amount);

    /// @notice Emitted when a successful deposit occurs
    /// @param sender Address that made the deposit
    /// @param token  Token address (address(0) for ETH)
    /// @param amount Amount deposited (in wei or USDC units)
    event KipuBankV3_DepositSuccess(address sender, address token, uint256 amount);

    /// @notice Emitted when a user is added to the blacklist
    event KipuBankV3_AddedToBlacklist(address user);

    /// @notice Emitted when a user is removed from the blacklist
    event KipuBankV3_RemovedFromBlacklist(address user);

    event KipuBankV3_SwappedToUSDC(address indexed sender, address indexed tokenIn, uint256 amountIn, uint256 usdcReceived);
    
    event KipuBankV3_UniswapRouterUpdated(address newRouter);

    //  ___________________
    // |                   |
    // |      ERRORS       |
    // |___________________|

    /// @notice error emitido cuando el monto es 0
    error KipuBankV3_ZeroAmount();

    /// @notice error emitido cuando retiro supera el umbral limite
    /// @param attemptedUSD   Monto en usd que se intento retirar
    error KipuBankV3_WithdrawalExceedsLimit(uint256 attemptedUSD);

    /// @notice error emitido cuando el banco supero el limite global de depositos
    /// @param attemptedAmount   Monto en wei que se intento depositar
    error KipuBankV3_BankExceedsGlobalCap(uint256 attemptedAmount);

    /// @notice error emitido cuando una transacción falla por saldo insuficiente
    /// @param user     Address de quien quiso retirar.
    /// @param token        Token in which the withdrawal was attempted
    /// @param amount       Monto en wei que quiso retirar.
    error KipuBankV3_InsufficientBalance(address user, address token, uint256 amount);

    /// @notice parametros de inicializacion invalidos
    /// @param withdrawCap    Capacidad maxima de retiro del banco.
    /// @param bankCap      Capacidad maxima de wei del banco.
    error KipuBankV3_InvalidInitialization(uint256 withdrawCap, uint256 bankCap);

    /// @notice error emited when the user is blacklisted
    error KipuBankV3_BlacklistedUser();

    ///@notice error emitted when address(0) is set for the router
    error KipuBankV3_InvalidRouter();

    ///@notice error emitted when trying to find path of two token's address that are the same
    error KipuBankV3_InvalidPath();

    //  _____________________
    // |                     |
    // |      MODIFIERS      |
    // |_____________________|

    /// @notice Verifies that the user has sufficient balance to perform the operation 
    /// @param _amount    Amount in wei
    modifier onlyDirectionsWithBalance(address _token, uint256 _amount) {
        if (_balances[msg.sender][_token] < _amount) revert KipuBankV3_InsufficientBalance(msg.sender, _token, _amount); 
        _;
    }

    /// @notice Verifies that the amount is higher than zero
    /// @param _amount    Amount in wei
    modifier nonZeroAmount(uint256 _amount) {
        if (_amount == 0) revert KipuBankV3_ZeroAmount();
        _;
    }

    /// @notice Verifies the sender is not blacklisted
    modifier onlyNotBlacklistedUsers() {
        if (blacklist[msg.sender]) revert KipuBankV3_BlacklistedUser();
        _;
    }

    //  _______________________
    // |                       |
    // |      CONSTRUCTOR      |
    // |_______________________|

    /// @param _owner            initial owner
    /// @param _usdc             address USDC token
    /// @param _withdrawalCapUsd withdrawal cap in USD (6 dec)
    /// @param _bankCapUsd       global cap in USD (6 dec)
    /// @param _router           router uniswap v2
    constructor(address _owner, address payable _router, address _usdc, uint256 _withdrawalCapUsd, uint256 _bankCapUsd) Ownable(_owner) {
        if (_bankCapUsd == 0 || _withdrawalCapUsd == 0 || _bankCapUsd < _withdrawalCapUsd) {
            revert KipuBankV3_InvalidInitialization(_withdrawalCapUsd, _bankCapUsd);
        }
        i_bankCap = _bankCapUsd;
        i_withdrawCap = _withdrawalCapUsd;
        i_usdc = IERC20(_usdc);
        s_router = IUniswapV2Router02(_router);
        s_weth = IUniswapV2Router02(_router).WETH();
    }

    //  _____________________
    // |                     |
    // |      FUNCTIONS      |
    // |_____________________|

    // RECEIVE y FALLBACK

    receive() external payable nonReentrant {
        _swapETHForUSDC(msg.sender, msg.value, 0); // 0 = sin slippage mínimo (puedes parametrizar)
    }

    fallback() external payable nonReentrant {
        _swapETHForUSDC(msg.sender, msg.value, 0);
    }

    // EXTERNAL 
    
    /// @notice Withdraw USDC from the user's vault
    /// @param _usdcAmount Amount to withdraw in USDC units
    function withdrawUSDC(uint256 _usdcAmount) external
        nonReentrant 
        onlyNotBlacklistedUsers  
        nonZeroAmount(_usdcAmount)
        onlyDirectionsWithBalance(address(i_usdc), _usdcAmount) 
        { 
        // Check 
        if (_usdcAmount > i_withdrawCap) revert KipuBankV3_WithdrawalExceedsLimit(_usdcAmount); 
        // Effects 
        _balances[msg.sender][address(i_usdc)] -= _usdcAmount; 
        _totalUSDCBank -= _usdcAmount; 
        _withdrawals[msg.sender][address(i_usdc)]++; 
        totalWithdrawals++; 
        
        // Interaction 
        i_usdc.safeTransfer(msg.sender, _usdcAmount);
        emit KipuBankV3_WithdrawalSuccess(msg.sender, _usdcAmount); 
    }
    
    /// @notice external deposit ETH
    function depositETH() external payable
        nonReentrant 
    {
        _swapETHForUSDC(msg.sender, msg.value, 0);
    }

    /// @dev USDC deposit 
    /// @param _usdcAmount   USDC amount received.
    function _depositUSDC(address _sender, uint256 _usdcAmount) internal {        
        uint256 _total = _totalUSDCBank + _usdcAmount;
        if(_total > i_bankCap) revert KipuBankV3_BankExceedsGlobalCap(_total);

        // Effects
        _totalUSDCBank += _usdcAmount;
        _balances[_sender][address(i_usdc)] += _usdcAmount;
        _deposits[_sender][address(i_usdc)]++;
        totalDeposits++;

        // Interactions
        i_usdc.safeTransferFrom(msg.sender, address(this), _usdcAmount);

        emit KipuBankV3_DepositSuccess(msg.sender, address(i_usdc), _usdcAmount);
    }

    /** * Depósito de cualquier ERC-20 soportado por Uniswap V2.
     * @param tokenIn       address del token a depositar
     * @param amountIn       cantidad a depositar
     * @param amountOutMin slippage del usuario en USDC
     * @param deadline       timestamp límite para el swap
     */
    function depositToken(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external nonReentrant onlyNotBlacklistedUsers nonZeroAmount(amountIn) {
        if (tokenIn == address(i_usdc)) {
            _depositUSDC(msg.sender, amountIn);
            return;
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).approve(address(s_router), 0);
            IERC20(tokenIn).approve(address(s_router), amountIn);

            // Ruta: TOKEN→USDC (vía WETH si hace falta)
            address[] memory path = _buildPath(tokenIn, address(i_usdc));

            // Chequeo de cap con estimación
            uint256 expectedOut = _quoteOut(amountIn, path);
            uint256 preTotal = _totalUSDCBank + expectedOut;
            if (preTotal > i_bankCap) revert KipuBankV3_BankExceedsGlobalCap(preTotal);

            uint256 usdcBefore = i_usdc.balanceOf(address(this));
            s_router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn, amountOutMin, path, address(this), deadline
            );
            uint256 usdcReceived = i_usdc.balanceOf(address(this)) - usdcBefore;

            uint256 postTotal = _totalUSDCBank + usdcReceived;
            if (postTotal > i_bankCap) revert KipuBankV3_BankExceedsGlobalCap(postTotal);

            _totalUSDCBank += usdcReceived;
            _balances[msg.sender][address(i_usdc)] += usdcReceived;
            _deposits[msg.sender][tokenIn]++;
            totalDeposits++;

            emit KipuBankV3_SwappedToUSDC(msg.sender, tokenIn, amountIn, usdcReceived);
            emit KipuBankV3_DepositSuccess(msg.sender, address(i_usdc), usdcReceived);
        }
    }
    
    /// @notice View current USDC balance (in USDC units)
    /// @return balance    USDC balance
    function getUsdcBalance() external view returns(uint256 balance){
        return _balances[msg.sender][address(i_usdc)];
    }

    // RESTRICTED FOR OWNER

    /// @notice Add user to the blacklist
    /// @param _user Address to be added to the blacklist
    function addToBlacklist(address _user) external onlyOwner {
        blacklist[_user] = true;
        emit KipuBankV3_AddedToBlacklist(_user);
    }

    /// @notice Add user to the blacklist
    /// @param _user Address to be added to the blacklist
    function removeFromBlacklist(address _user) external onlyOwner {
        blacklist[_user] = false;
        emit KipuBankV3_RemovedFromBlacklist(_user);
    }

    function setRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert KipuBankV3_InvalidRouter();

        s_router = IUniswapV2Router02(_router);
        s_weth = IUniswapV2Router02(_router).WETH();

        emit KipuBankV3_UniswapRouterUpdated(_router);
    }

    // PRIVATE 

    function _swapETHForUSDC(address _sender, uint256 _ethAmount, uint256 _amountOutMin) internal {
        if (_ethAmount == 0) revert KipuBankV3_ZeroAmount();

        address[] memory path = new address[](2);
        path[0] = s_weth;
        path[1] = address(i_usdc);

        uint256 preBalance = i_usdc.balanceOf(address(this));

        s_router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: _ethAmount }(
            _amountOutMin, 
            path, 
            address(this), 
            block.timestamp + 300
        );

        uint256 received = i_usdc.balanceOf(address(this)) - preBalance;

        uint256 totalAfter = _totalUSDCBank + received;
        if (totalAfter > i_bankCap) revert KipuBankV3_BankExceedsGlobalCap(totalAfter);

        _totalUSDCBank = totalAfter;
        _balances[_sender][address(i_usdc)] += received;
        _deposits[_sender][s_weth]++; // opcional: marcar como depósito en ETH

        totalDeposits++;

        emit KipuBankV3_SwappedToUSDC(_sender, s_weth, _ethAmount, received);
        emit KipuBankV3_DepositSuccess(_sender, address(i_usdc), received);
    }

    // UNISWAP HELPERS

    /// builds path between ERC-20 token and USDC
    /// @param tokenIn Token that's being traded
    /// @param tokenOut USDC
    function _buildPath(address tokenIn, address tokenOut) internal view returns (address[] memory path) {
        if (tokenIn == tokenOut) revert KipuBankV3_InvalidPath();

        if (tokenIn == s_weth || tokenOut == s_weth) {
            path = new address[](2);
            path[0] = tokenIn; 
            path[1] = tokenOut;

        } else {
            path = new address[](3);
            path[0] = tokenIn; 
            path[1] = s_weth; 
            path[2] = tokenOut;
        }
    }

    /// estimates the amount of usdc resulting from trade
    /// @param amountIn amount of tokens entered
    /// @param path     path between token that's being traded and USDC
    function _quoteOut(uint256 amountIn, address[] memory path) internal view returns (uint256) {
        uint[] memory amounts = s_router.getAmountsOut(amountIn, path);

        return amounts[amounts.length - 1];
    }
}