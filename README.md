# KipuBank V2

Vault for ETH and USDC with per-transaction and global limits in USD.

## Features
- ETH and USDC deposits and withdrawals per user
- Withdrawal limit (`withdrawCap`, `immutable`)
- Global bank limit (`bankCap`, `immutable`, in USD)
- Custom errors and detailed events
- Safe design pattern: checks → effects → interactions
- Personal balance and total bank queries
- Blacklist system for restricted addresses
- Chainlink ETH/USD price feed integration (Sepolia)

## Deployment (Remix, Metamask, SepoliaETH)

### Constructor

```solidity
/// @param _owner        Initial owner address
/// @param _feed         Chainlink ETH/USD feed (Sepolia)
/// @param _usdc         USDC token address
/// @param _withdrawCapUsd  Max withdrawal per transaction (in USD, 6 decimals)
/// @param _bankCapUsd      Max total USD capacity of the bank (in USD, 6 decimals)
constructor(
    address _owner,
    address _feed,
    address _usdc,
    uint256 _withdrawCapUsd,
    uint256 _bankCapUsd
)

```
Example parameters

```solidity
_owner         = 0xYourWalletAddress
_feed          = 0x694AA1769357215DE4FAC081bf1f309aDC325306  // ETH/USD Chainlink Feed
_usdc          = 0xf08a50178dfcde18524640ea6618a1f965821715  // USDC (Sepolia)
_withdrawCapUsd = 5000000000   // 5,000 USD (6 decimals)
_bankCapUsd     = 100000000000 // 100,000 USD (6 decimals)
```

### Remix

- Connect MetaMask: 
- - Deploy & Run Transactions → Environment → Injected Provider - MetaMask

- Compile:

- - Solidity Compiler tab -> Select version 0.8.24 or higher -> Click Compile KipuBankV2.sol

- Deploy:

- - In Deploy & Run Transactions, fill in the constructor parameters above.
- - Click Deploy.
- - Confirm the transaction in MetaMask.

## Interacting with the Contract (Remix + MetaMask + Sepolia)

### Deposit ETH:

- En la parte de arriba de la de Remix hay un campo que dice Value.
- At the top of `Deploy & run transactions` in Remix, in the Value field, enter the amount of ETH/gwei/wei you want to deposit (e.g., 1 ETH).
- Click the depositETH button (red).
- Confirm in MetaMask.

*The event KipuBankV2_DepositSuccess will appear in the Remix console.*

### Deposit USDC:

- Call
```solidity
depositUSDC(<amount>); deposits 100 USDC (since USDC has 6 decimals).
```

*The event KipuBankV2_DepositSuccess will appear in the Remix console.*

### Withdraw ETH:

- Enter the amount to withdraw in wei in `withdrawETH(uint256 _weiAmount)`.
- Click Transact.
- Confirm in MetaMask.

*If successful, the event KipuBankV2_WithdrawalSuccess will be emitted.*

### Withdraw USDC:

- Enter the amount to withdraw in USDC in `withdrawUSDC(uint256 _usdcAmount)`.
- Click Transact.
- Confirm in MetaMask.

*If successful, the event KipuBankV2_WithdrawalSuccess will be emitted.*

### Check Balances and Stats:

| Action            | Function               | Returns                             |
| ----------------- | ---------------------- | ----------------------------------- |
| View ETH balance  | `getEthBalance()`      | Balance in wei                      |
| View USDC balance | `getUsdcBalance()`     | Balance in 6-decimals               |
| View total in USD | `getTotalUsdBalance()` | Total ETH (converted to USD) + USDC |
| Total deposits    | `totalDeposits()`      | Number of successful deposits       |
| Total withdrawals | `totalWithdrawals()`   | Number of successful withdrawals    |
| Bank cap          | `i_bankCap()`          | Global USD limit                    |
| Withdrawal cap    | `i_withdrawCap()`      | Per-transaction USD limit           |
