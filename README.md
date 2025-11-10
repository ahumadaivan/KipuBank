# KipuBank V3

Bóveda que convierte depósitos (ETH o ERC20) a USDC usando Uniswap V2.

## Características

  * Permite depositar ETH y cualquier token ERC20 (vía Uniswap V2).
  * **Todos los depósitos se convierten y almacenan como USDC.**
  * Los retiros son únicamente en **USDC**.
  * Límite por transacción de retiro: `i_withdrawCap` (en **unidades de USDC**, 6 decimales).
  * Límite global del banco: `i_bankCap` (en **unidades de USDC**, 6 decimales).
  * Errores personalizados, eventos, checks-effects-interactions.
  * Consulta de saldo personal (en USDC).

## Despliegue (Remix, Metamask, SepoliaETH)

### Constructor

```solidity
/// @param _owner               Dirección del dueño (tu Metamask)
/// @param _router              Dirección del Router de Uniswap V2
/// @param _usdc                Dirección del token USDC
/// @param _withdrawalCapUsd    Límite por retiro (en unidades de USDC, 6 decimales)
/// @param _bankCapUsd          Límite global del banco (en unidades de USDC, 6 decimales)
constructor(
    address _owner,
    address payable _router,
    address _usdc,
    uint256 _withdrawalCapUsd,
    uint256 _bankCapUsd
) ...
```

### Remix

  * Conectar Metamask:

      * `Deploy & Run Transactions` -\> `Environment` -\> `Injected Provider - Metamask`

  * Compilar contrato:

      * Pestaña `Solidity Compiler` -\> elegir versión `0.8.24` (o superior) -\> `Compile KipuBankV3.sol`

  * Deploy:

      * En `Deploy` ingresar argumentos del constructor.
      * **Ejemplo para Sepolia:**

    <!-- end list -->

    ```text
    _owner: (Tu dirección de Metamask se autocompleta si dejas el campo vacío)
    _router: 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3
    _usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
    _withdrawalCapUsd: 1000000000 (Ej. 1,000 USDC)
    _bankCapUsd: 10000000000 (Ej. 10,000 USDC)
    ```

      * Confirmar en Metamask.

## Interactuar con el contrato (Remix, Metamask, SepoliaETH)

### Depositar ETH

Hay dos formas:

1.  **Usando `depositETH()`:**

      * En la parte de arriba de Remix, en el campo `Value`, poné cuánto querés mandar. Ejemplo: `0.1` ETH.
      * Hacé clic en el botón naranja `depositETH`.
      * Confirmá en Metamask.

2.  **Usando `fallback()` / `receive()`:**

      * En el campo `Value`, poné el monto (ej. `0.1` ETH).
      * Hacé clic en el botón rojo `Transact (Fallback)`.
      * Confirmá en Metamask.

Ambos métodos swapearán tu ETH por USDC y lo acreditarán a tu saldo.

### Depositar Tokens ERC20 (ej. USDC u otro)

Este es un proceso de **dos pasos**:

**Paso 1: Aprobar (Solo se hace una vez por token)**

  * Andá al contrato del token que querés depositar (ej. USDC: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`).
  * Podés cargarlo en Remix usando el campo `At Address` en la pestaña `Deploy`.
  * En el contrato del *token*, llamá a la función `approve`.
      * `spender`: La dirección de **tu contrato KipuBankV3** desplegado.
      * `amount`: Un monto alto (ej. `1000000000000000000000000`).
  * Confirmá la transacción de aprobación.

**Paso 2: Depositar**

  * Volvé a tu contrato `KipuBankV3` en Remix.
  * Buscá la función `depositToken`.
      * `tokenIn`: La dirección del token que estás depositando (ej. `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` para USDC).
      * `amountIn`: El monto (en la menor unidad del token).
          * *Ejemplo para 10 USDC (6 decimales):* `10000000`
      * `amountOutMin`: `0` (para pruebas está bien).
      * `deadline`: Un timestamp futuro. (Buscá "Unix timestamp" en Google y copiá el número).
  * Hacé clic en `transact` y confirmá en Metamask.

### Retirar (siempre en USDC)

  * En el campo de `withdrawUSDC(uint256 _usdcAmount)` poné el monto en **unidades de USDC (6 decimales)**.
      * *Ejemplo para 10 USDC:* `10000000`
  * Hacé clic en `transact`.
  * Confirmá en Metamask.

### Consultar

  * Clic en `getUsdcBalance()` para ver tu balance en el banco (en unidades de USDC).
  * Clic en `totalDeposits()` y `totalWithdrawals()` para ver estadísticas.
  * Clic en `i_bankCap()` y `i_withdrawCap()` para ver los umbrales (en unidades de USDC).