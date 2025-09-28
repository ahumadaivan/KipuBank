// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title KipuBank
/// @author ahumadaivan
/// @notice Permite a cada usuario depositar y retirar ETH con un tope por transacción y un tope global del banco.

contract KipuBank {

    //   _________________________
    //  |                         |
    //  |      VAR DE ESTADO      |
    //  |_________________________|

    /// @notice balance en wei de cada cuenta
    mapping (address => uint256) private balances;

    /// @notice cantidad de depositos de cada cuenta
    mapping (address => uint256) private depositos;

    /// @notice cantidad de retiros de cada cuenta
    mapping (address => uint256) private retiros;

    /// @notice total de wei en el banco
    uint256 private _totalContenidoBanco;

    /// @notice contadores de depositos y retiros
    uint64 public totalDepositos;
    uint64 public totalRetiros;

    /// @notice limites de retiro y de wei en el banco
    uint256 public immutable retiroCap;
    uint256 public immutable bankCap;


    //   ___________________
    //  |                   |
    //  |      EVENTOS      |
    //  |___________________|

    /// @notice evento emitido cuando se realiza un retiro exitoso de una cuenta
    /// @param receiver     Address que recibió el retiro
    /// @param monto        Monto en wei que recibio
    event KipuBank_RetiroExitoso(address receiver, uint256 monto);

    /// @notice evento emitido cuando se realiza un deposito exitoso en una cuenta
    /// @param sender       Address que realizó el depósito
    /// @param monto        Monto en wei depositado
    event KipuBank_DepositoExitoso(address sender, uint256 monto);

    //   ___________________
    //  |                   |
    //  |      ERRORES      |
    //  |___________________|

    /// @notice error emitido cuando el monto es 0
    error KipuBank_MontoCero();

    /// @notice error emitido cuando retiro supera el umbral limite
    /// @param retiroSuperado   Monto en wei que se intento retirar
    error KipuBank_RetiroSuperaLimite(uint256 retiroSuperado);

    /// @notice error emitido cuando el banco supero el limite global de depositos
    /// @param _monto   Monto en wei que se intento depositar
    error KipuBank_BancoSuperaLimiteGlobal(uint256 _monto);

    /// @notice error emitido cuando una transacción nativa falla
    /// @param sender       Address de quien quiso retirar.
    /// @param monto        Monto en wei que quiso retirar.
    error KipuBank_RetiroFallido(address sender, uint256 monto); 

    /// @notice error emitido cuando una transacción falla por saldo insuficiente
    /// @param sender       Address de quien quiso retirar.
    /// @param monto        Monto en wei que quiso retirar.
    error KipuBank_SaldoInsuficiente(address sender, uint256 monto); 

    /// @notice parametros de inicializacion invalidos
    /// @param retiroCap    Capacidad maxima de retiro del banco.
    /// @param bankCap      Capacidad maxima de wei del banco.
    error KipuBank_ParametrosInicio(uint256 retiroCap, uint256 bankCap); 


    //   _____________________
    //  |                     |
    //  |      MODIFIERS      |
    //  |_____________________|


    modifier soloDireccionesConSaldo(uint256 _monto) {
        if (balances[msg.sender] < _monto) revert KipuBank_SaldoInsuficiente(msg.sender, _monto); 
        _;
    }

    modifier soloMontosMayoresACero(uint256 _monto) {
        if (_monto == 0) revert KipuBank_MontoCero();
        _;
    }

    //   _______________________
    //  |                       |
    //  |      CONSTRUCTOR      |
    //  |_______________________|


    /// @param _retiroCap   Límite por transacción para retirar em wei.
    /// @param _bankCap     Límite global máximo que puede custodiar el banco en wei.
    constructor(uint256 _retiroCap, uint256 _bankCap) {
        if (_retiroCap == 0 || _bankCap == 0 || _bankCap < _retiroCap) {
            revert KipuBank_ParametrosInicio(_retiroCap, _bankCap);
        }
        bankCap = _bankCap;
        retiroCap = _retiroCap;
    }

    //   _____________________
    //  |                     |
    //  |      FUNCIONES      |
    //  |_____________________|

    // RECEIVE y FALLBACK


    receive() external payable {
        _deposit(msg.sender, msg.value);
    }

    fallback() external payable{
        if (msg.value == 0) revert KipuBank_MontoCero();
        _deposit(msg.sender, msg.value);
    }

    // EXTERNAL 


    /// @notice Retirar ETH de tu bóveda personal respetando el límite por transacción.
    /// @param monto    Cantidad a retirar en wei.
    function retirar(uint256 monto) external soloDireccionesConSaldo(monto) soloMontosMayoresACero(monto) {
        // Check
        if (monto > retiroCap) revert KipuBank_RetiroSuperaLimite(monto); 
        
        // Effects
        balances[msg.sender] -= monto; 
        _totalContenidoBanco -= monto;
        retiros[msg.sender]++;
        totalRetiros++;

        // Interaction
        _retirarEth(msg.sender, monto);

        emit KipuBank_RetiroExitoso(msg.sender, monto);
    }

    /// @notice Depositar ETH en tu bóveda personal.
    function depositar() external payable {
        _deposit(msg.sender, msg.value);
    }

    /// @notice Consultar el saldo propio.
    /// @return balance    Saldo actual en wei.
    function consultarSaldo() external view returns(uint256 balance){
        return balances[msg.sender];
    }


    // PRIVATE 

    /// @dev Envío nativo seguro con call, revierte si falla.
    /// @param _receiver     Destinatario.
    /// @param _monto       Monto en wei.
    function _retirarEth(address _receiver, uint256 _monto) private  {
        (bool exito, ) = _receiver.call{value: _monto}("");
        if(!exito) revert KipuBank_RetiroFallido(_receiver, _monto);
    }

    /// @dev Lógica compartida de depósito. Valida cap global y actualiza estado.
    /// @param _sender  Dirección a acreditar.
    /// @param _monto   Monto en wei recibido.
    function _deposit(address _sender, uint256 _monto) private soloMontosMayoresACero(_monto) {
        // Check
        if (_totalContenidoBanco + _monto > bankCap) revert KipuBank_BancoSuperaLimiteGlobal(_monto);
        
        // Effects
        _totalContenidoBanco += _monto;
        balances[_sender] += _monto;
        depositos[_sender]++;
        totalDepositos++;

        emit KipuBank_DepositoExitoso(_sender, _monto);
    }
}