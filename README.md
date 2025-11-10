# KipuBank V3

A vault that converts deposits (ETH or ERC20) into USDC using Uniswap V2.

## Features

  * Allows depositing ETH and any ERC20 token (via Uniswap V2).
  * **All deposits are converted and stored as USDC.**
  * Withdrawals are only in **USDC**.
  * Per-transaction withdrawal limit: `i_withdrawCap` (in **USDC units**, 6 decimals).
  * Global bank limit: `i_bankCap` (in **USDC units**, 6 decimals).
  * Custom errors, events, checks-effects-interactions.
  * Personal balance query (in USDC).

## Deployment (Remix, Metamask, SepoliaETH)

### Constructor

```solidity
/// @param _owner               The owner's address (your Metamask)
/// @param _router              Uniswap V2 Router address
/// @param _usdc                USDC token address
/// @param _withdrawalCapUsd    Withdrawal limit per transaction (in USDC units, 6 decimals)
/// @param _bankCapUsd          Global bank limit (in USDC units, 6 decimals)
constructor(
    address _owner,
    address payable _router,
    address _usdc,
    uint256 _withdrawalCapUsd,
    uint256 _bankCapUsd
) ...
```

### Remix

  * Connect Metamask:

      * `Deploy & Run Transactions` -\> `Environment` -\> `Injected Provider - Metamask`

  * Compile Contract:

      * `Solidity Compiler` tab -\> select version `0.8.24` (or higher) -\> `Compile KipuBankV3.sol`

  * Deploy:

      * Enter the constructor arguments in the `Deploy` section.
      * **Example for Sepolia:**

    <!-- end list -->

    ```text
    _owner: (Your Metamask address auto-fills if you leave this blank)
    _router: 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3
    _usdc: 0xbe72E441BF55620febc26715db68d3494213D8Cb
    _withdrawalCapUsd: 1000000000 (e.g., 1,000 USDC)
    _bankCapUsd: 10000000000 (e.g., 10,000 USDC)
    ```

      * Confirm in Metamask.

## Interacting with the Contract (Remix, Metamask, SepoliaETH)

### Deposit ETH

There are two ways:

1.  **Using `depositETH()`:**

      * In the `Value` field at the top of the Remix panel, enter the amount. Example: `0.1` ETH.
      * Click the orange `depositETH` button.
      * Confirm in Metamask.

2.  **Using `fallback()` / `receive()`:**

      * In the `Value` field, enter the amount (e.g., `0.1` ETH).
      * Click the red `Transact (Fallback)` button.
      * Confirm in Metamask.

Both methods will swap your ETH for USDC and credit your balance.

### Deposit ERC20 Tokens (e.g., USDC or others)

This is a **two-step process**:

**Step 1: Approve (Only done once per token)**

  * Go to the contract of the token you want to deposit (e.g., USDC: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`).
  * You can load it in Remix using the `At Address` field in the `Deploy` tab.
  * In the *token's* contract, call the `approve` function.
      * `spender`: The address of **your deployed KipuBankV3 contract**.
      * `amount`: A large amount (e.g., `1000000000000000000000000`).
  * Confirm the approval transaction.

**Step 2: Deposit**

  * Return to your `KipuBankV3` contract in Remix.
  * Find the `depositToken` function.
      * `tokenIn`: The address of the token you are depositing (e.g., `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` for USDC).
      * `amountIn`: The amount (in the token's smallest unit).
          * *Example for 10 USDC (6 decimals):* `10000000`
      * `amountOutMin`: `0` (this is fine for testing).
      * `deadline`: A future timestamp. (Search "Unix timestamp" on Google and copy the number).
  * Click `transact` and confirm in Metamask.

### Withdraw (always in USDC)

  * In the `withdrawUSDC(uint256 _usdcAmount)` field, enter the amount in **USDC units (6 decimals)**.
      * *Example for 10 USDC:* `10000000`
  * Click `transact`.
  * Confirm in Metamask.

### Check Balance

  * Click `getUsdcBalance()` to see your balance in the bank (in USDC units).
  * Click `totalDeposits()` and `totalWithdrawals()` to see statistics.
  * Click `i_bankCap()` and `i_withdrawCap()` to see the thresholds (in USDC units).

## Design Decisions & Trade-offs

* **All to USDC:**
    * **Pro:** The vault is stable and unaffected by market volatility.
    * **Con:** The user doesn't benefit if their deposited token (e.g., ETH) goes up in price. The user also pays the swap slippage cost.

* **Fixed Caps (`i_bankCap`, `i_withdrawCap`):**
    * **Pro:** They protect the contract. The global cap (`i_bankCap`) limits the "blast radius" of a hack, and the withdrawal cap (`i_withdrawCap`) slows an attacker down.
    * **Con:** They are `immutable`. To raise or lower them, you must deploy an entirely new contract.

* **Owner Control (Router & Blacklist):**
    * **Pro:** The owner can update the Uniswap router if needed and block malicious addresses.