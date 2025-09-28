# KipuBank

Bóveda de ETH con límite por transacción y límite global.

## Características
- Depósitos y retiros de ETH por usuario
- Límite por transacción: `retiroCap` (inmutable)
- Límite global del banco: `bankCap` (inmutable)
- Errores personalizados, eventos, checks-effects-interactions
- Consulta de saldo personal

## Despliegue (Remix, Metamask, SepoliaETH)

### Constructor

```solidity
/// @param _retiroCap   Límite por transacción para retirar em wei.
/// @param _bankCap     Límite global máximo que puede custodiar el banco en wei.
constructor(uint256 _retiroCap, uint256 _bankCap) {
    ...
}
```

### Remix

- Conectar Metamask: 
- - Deploy & Run Transactions -> Environment -> Injected Provider - Metamask


- Compilar contrato:

- - Pestaña Solidity Compiler -> elegir versión 0.8.24 (o superior) -> Compile KipuBank.sol

- Deploy:

- - En Deploy ingresar argumentos del constructor, ej.:

```solidity
// Ingresar en wei
// 1 ether, 5 ether
1000000000000000000, 5000000000000000000
```

- - Confirmar en Metamask

## Interactuar con el contrato (Remix, Metamask, SepoliaETH)

### Depositar:

- En la parte de arriba de la pestaña `Deploy & run transactions` de Remix hay un campo que dice Value.
- Poné ahí cuánto querés mandar. Ejemplo: 1 eth.
- Clic en el botón rojo depositar.
- Confirmá en Metamask.

### Retirar:

- En el campo de `retirar(uint256 monto)` poné el monto en wei.
- Clic en Transact.
- Confirmá en Metamask.

### Consultar:

- Clic en consultarSaldo() para ver tu balance en el banco.
- Clic en totalDepositos() y totalRetiros() para ver estadísticas.
- Clic en bankCap() y retiroCap() para ver los umbrales.