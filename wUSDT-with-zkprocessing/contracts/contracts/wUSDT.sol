pragma solidity ^0.7.0;

import "./IERC20.sol";
import "./IUSDT.sol";
import "./ECRecover.sol";
import "./EIP712.sol";
import "./Governance.sol";
import "./Utils.sol";
import "./SafeMath.sol";

contract wUSDT is IERC20, EIP712Domain {
    using SafeMath for uint256;

    string  public name     = "Wrapped USDT";
    string  public symbol   = "wUSDT";
    uint8   public decimals = 6;

    mapping(address => uint256) internal balances;
    mapping(address => mapping(address => uint256)) internal allowed;
    uint256 internal totalSupply_ = 0;

    Governance public governance;

    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Burn(address indexed burner, address indexed to, uint256 amount);

    address public USDT;

    uint256 internal rootHash;

    uint256 constant BLOCK_TIMESTAMP_CAN_NOT_BE_OLDER = 3 hours;
    uint256 constant BLOCK_TIMESTAMP_POSSIBLE_DELTA = 1 minutes;

    constructor(Governance _governance, address _USDT, uint256 _initialRootHash) public {
        governance = _governance;
        USDT = _USDT;
        rootHash = _initialRootHash;

        DOMAIN_SEPARATOR = EIP712.makeDomainSeparator("wUSDT", "1");
    }

    event FeeCollected(address indexed from, address feeAccount, uint256 fee);

    uint256 constant BYTES_PER_TRANSACTION = 128;

    function _cheapTransactionsProcessing(
        bytes memory _transactionsData,
        bytes memory _transactionsToProcess,
        address _feeAccount
    ) internal {
        uint256 totalFee = 0;
        for (uint256 i = 0; i + BYTES_PER_TRANSACTION - 1 < _transactionsData.length; i += BYTES_PER_TRANSACTION) {
            if (uint8(_transactionsToProcess[i / BYTES_PER_TRANSACTION]) != 0) {
                bytes memory currentTransactionBytes = Utils.slice(_transactionsData, i, BYTES_PER_TRANSACTION);
                (
                    address from,
                    address to,
                    uint256 amount,
                    uint256 fee
                ) = abi.decode(currentTransactionBytes, (address, address, uint256, uint256));
                if (balances[from] >= amount.add(fee)) {
                    balances[from] = balances[from].sub(amount.add(fee));
                    balances[to] = balances[to].add(amount);
                    emit Transfer(from, to, amount);

                    totalFee = totalFee.add(fee);
                    emit FeeCollected(from, _feeAccount, fee);
                }
            }
        }

        balances[_feeAccount] = balances[_feeAccount].add(totalFee);
    }

    function proveBlock(
        uint256 _newStorageRoot,
        address _feeAccount,
        uint256 _blockTimestamp,
        bytes calldata _transactionsData,
        bytes calldata _transactionsToProcess
    ) external {
        require(governance.isOperatorValid(msg.sender));

        bytes32 commitment = sha256(abi.encodePacked(rootHash, _newStorageRoot));
        commitment = sha256(abi.encodePacked(commitment, _feeAccount));
        commitment = sha256(abi.encodePacked(commitment, _blockTimestamp));
        commitment = sha256(abi.encodePacked(commitment, _transactionsData));
        /// TODO :)
        /// verify circuit with `commitment` as an input

        // require(_blockTimestamp >= block.timestamp - BLOCK_TIMESTAMP_CAN_NOT_BE_OLDER);
        // require(_blockTimestamp <= block.timestamp + BLOCK_TIMESTAMP_POSSIBLE_DELTA);

        _cheapTransactionsProcessing(_transactionsData, _transactionsToProcess, _feeAccount);

        rootHash = _newStorageRoot;
    }

    /**
     * @dev Function to mint tokens
     * @param _to The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint. Must be less than or equal
     * to the minterAllowance of the caller.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(address _to, uint256 _amount) external returns (bool) {
        require(_to != address(0), "mint to the zero address");
        require(_amount > 0, "mint amount not greater than 0");

        IUSDT(USDT).transferFrom(msg.sender, address(this), _amount);

        totalSupply_ = totalSupply_.add(_amount);
        balances[_to] = balances[_to].add(_amount);

        emit Mint(msg.sender, _to, _amount);
        emit Transfer(address(0), _to, _amount);
        return true;
    }

    /**
     * @dev allows to burn some of tokens
     * amount is less than or equal to the minter's account balance
     * @param _to The address that will receive equivalent amount of USDT tokens
     * @param _amount uint256 the amount of tokens to be burned
     */
    function burn(address _to, uint256 _amount) external returns (bool) {
        uint256 balance = balances[msg.sender];
        require(_amount > 0, "burn amount not greater than 0");
        require(balance >= _amount, "burn amount exceeds balance");

        totalSupply_ = totalSupply_.sub(_amount);
        balances[msg.sender] = balance.sub(_amount);

        IUSDT(USDT).transfer(_to, _amount);

        emit Burn(msg.sender, _to, _amount);
        emit Transfer(msg.sender, address(0), _amount);
        return true;
    }

    /**
     * @notice Amount of remaining tokens spender is allowed to transfer on
     * behalf of the token owner
     * @param owner     Token owner's address
     * @param spender   Spender's address
     * @return Allowance amount
     */
    function allowance(address owner, address spender) external override view returns (uint256) {
        return allowed[owner][spender];
    }

    /**
     * @dev Get totalSupply of token
     */
    function totalSupply() external override view returns (uint256) {
        return totalSupply_;
    }

    /**
     * @dev Get token balance of an account
     * @param account address The account
     */
    function balanceOf(address account) external override view returns (uint256) {
        return balances[account];
    }

    /**
     * @notice Set spender's allowance over the caller's tokens to be a given
     * value.
     * @param spender   Spender's address
     * @param value     Allowance amount
     * @return True if successful
     */
    function approve(address spender, uint256 value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Internal function to set allowance
     * @param owner     Token owner's address
     * @param spender   Spender's address
     * @param value     Allowance amount
     */
    function _approve(
        address owner,
        address spender,
        uint256 value
    ) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        allowed[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /**
     * @notice Transfer tokens by spending allowance
     * @param from  Payer's address
     * @param to    Payee's address
     * @param value Transfer amount
     * @return True if successful
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        require(
            value <= allowed[from][msg.sender],
            "ERC20: transfer amount exceeds allowance"
        );
        _transfer(from, to, value);
        allowed[from][msg.sender] = allowed[from][msg.sender].sub(value);
        return true;
    }

    /**
     * @notice Transfer tokens from the caller
     * @param to    Payee's address
     * @param value Transfer amount
     * @return True if successful
     */
    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @notice Internal function to process transfers
     * @param from  Payer's address
     * @param to    Payee's address
     * @param value Transfer amount
     */
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(
            value <= balances[from],
            "ERC20: transfer amount exceeds balance"
        );

        balances[from] = balances[from].sub(value);
        balances[to] = balances[to].add(value);
        emit Transfer(from, to, value);
    }

    bytes32
    public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = 0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;
    // = keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32
    public constant TRANSFER_WITH_AUTHORIZATION_WITH_FEE_TYPEHASH = 0x68e70df5bee84511c3efcc3337d7e20877fd87cf02e5628dcec5d893834a76fc;
    // = keccak256("TransferWithAuthorizationWithFee(address from,address to,uint256 value,uint256 fee,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32
    public constant APPROVE_WITH_AUTHORIZATION_TYPEHASH = 0x808c10407a796f3ef2c7ea38c0638ea9d2b8a1c63e3ca9e1f56ce84ae59df73c;
    // = keccak256("ApproveWithAuthorization(address owner,address spender,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32
    public constant INCREASE_ALLOWANCE_WITH_AUTHORIZATION_TYPEHASH = 0x424222bb050a1f7f14017232a5671f2680a2d3420f504bd565cf03035c53198a;
    // = keccak256("IncreaseAllowanceWithAuthorization(address owner,address spender,uint256 increment,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32
    public constant DECREASE_ALLOWANCE_WITH_AUTHORIZATION_TYPEHASH = 0xb70559e94cbda91958ebec07f9b65b3b490097c8d25c8dacd71105df1015b6d8;
    // = keccak256("DecreaseAllowanceWithAuthorization(address owner,address spender,uint256 decrement,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32
    public constant CANCEL_AUTHORIZATION_TYPEHASH = 0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;
    // = keccak256("CancelAuthorization(address authorizer,bytes32 nonce)")

    enum AuthorizationState { Unused, Used, Canceled }

    /**
     * @dev authorizer address => nonce => authorization state
     */
    mapping(address => mapping(bytes32 => AuthorizationState)) private _authorizationStates;

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    /**
     * @notice Returns the state of an authorization
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @return Authorization state
     */
    function authorizationState(address authorizer, bytes32 nonce) external view returns (AuthorizationState) {
        return _authorizationStates[authorizer][nonce];
    }

    /**
     * @notice Verify a signed transfer authorization and execute if valid
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function _transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        _requireValidAuthorization(from, nonce, validAfter, validBefore);

        bytes memory data = abi.encode(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce
        );
        require(
            EIP712.recover(DOMAIN_SEPARATOR, v, r, s, data) == from,
            "invalid signature"
        );

        _markAuthorizationAsUsed(from, nonce);
        _transfer(from, to, value);
    }

    /**
     * @notice Verify a signed transfer authorization and execute if valid
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param fee           Fee to be transferred to fee account
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param feeAccount    Account to receive fee
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function _transferWithAuthorizationWithFee(
        address from,
        address to,
        uint256 value,
        uint256 fee,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        address feeAccount,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        _requireValidAuthorization(from, nonce, validAfter, validBefore);

        bytes memory data = abi.encode(
            TRANSFER_WITH_AUTHORIZATION_WITH_FEE_TYPEHASH,
            from,
            to,
            value,
            fee,
            validAfter,
            validBefore,
            nonce
        );
        require(
            EIP712.recover(DOMAIN_SEPARATOR, v, r, s, data) == from,
            "invalid signature"
        );

        _markAuthorizationAsUsed(from, nonce);
        _transfer(from, feeAccount, fee);
        _transfer(from, to, value);
    }

    /**
     * @notice Verify a signed authorization for an increase in the allowance
     * granted to the spender and execute if valid
     * @param owner         Token owner's address (Authorizer)
     * @param spender       Spender's address
     * @param increment     Amount of increase in allowance
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function _increaseAllowanceWithAuthorization(
        address owner,
        address spender,
        uint256 increment,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        _requireValidAuthorization(owner, nonce, validAfter, validBefore);

        bytes memory data = abi.encode(
            INCREASE_ALLOWANCE_WITH_AUTHORIZATION_TYPEHASH,
            owner,
            spender,
            increment,
            validAfter,
            validBefore,
            nonce
        );
        require(
            EIP712.recover(DOMAIN_SEPARATOR, v, r, s, data) == owner,
            "invalid signature"
        );

        _markAuthorizationAsUsed(owner, nonce);
        _increaseAllowance(owner, spender, increment);
    }

    /**
     * @notice Verify a signed authorization for a decrease in the allowance
     * granted to the spender and execute if valid
     * @param owner         Token owner's address (Authorizer)
     * @param spender       Spender's address
     * @param decrement     Amount of decrease in allowance
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function _decreaseAllowanceWithAuthorization(
        address owner,
        address spender,
        uint256 decrement,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        _requireValidAuthorization(owner, nonce, validAfter, validBefore);

        bytes memory data = abi.encode(
            DECREASE_ALLOWANCE_WITH_AUTHORIZATION_TYPEHASH,
            owner,
            spender,
            decrement,
            validAfter,
            validBefore,
            nonce
        );
        require(
            EIP712.recover(DOMAIN_SEPARATOR, v, r, s, data) == owner,
            "invalid signature"
        );

        _markAuthorizationAsUsed(owner, nonce);
        _decreaseAllowance(owner, spender, decrement);
    }

    /**
     * @notice Verify a signed approval authorization and execute if valid
     * @param owner         Token owner's address (Authorizer)
     * @param spender       Spender's address
     * @param value         Amount of allowance
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function _approveWithAuthorization(
        address owner,
        address spender,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        _requireValidAuthorization(owner, nonce, validAfter, validBefore);

        bytes memory data = abi.encode(
            APPROVE_WITH_AUTHORIZATION_TYPEHASH,
            owner,
            spender,
            value,
            validAfter,
            validBefore,
            nonce
        );
        require(
            EIP712.recover(DOMAIN_SEPARATOR, v, r, s, data) == owner,
            "invalid signature"
        );

        _markAuthorizationAsUsed(owner, nonce);
        _approve(owner, spender, value);
    }

    /**
     * @notice Attempt to cancel an authorization
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function _cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        _requireUnusedAuthorization(authorizer, nonce);

        bytes memory data = abi.encode(
            CANCEL_AUTHORIZATION_TYPEHASH,
            authorizer,
            nonce
        );
        require(
            EIP712.recover(DOMAIN_SEPARATOR, v, r, s, data) == authorizer,
            "invalid signature"
        );

        _authorizationStates[authorizer][nonce] = AuthorizationState.Canceled;
        emit AuthorizationCanceled(authorizer, nonce);
    }

    /**
     * @notice Check that an authorization is unused
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     */
    function _requireUnusedAuthorization(address authorizer, bytes32 nonce) private view {
        require(
            _authorizationStates[authorizer][nonce] ==
            AuthorizationState.Unused,
            "authorization is used or canceled"
        );
    }

    /**
     * @notice Check that authorization is valid
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     */
    function _requireValidAuthorization(
        address authorizer,
        bytes32 nonce,
        uint256 validAfter,
        uint256 validBefore
    ) private view {
        require(
            block.timestamp > validAfter,
            "authorization is not yet valid"
        );
        require(block.timestamp < validBefore, "authorization is expired");
        _requireUnusedAuthorization(authorizer, nonce);
    }

    /**
     * @notice Mark an authorization as used
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     */
    function _markAuthorizationAsUsed(address authorizer, bytes32 nonce) private {
        _authorizationStates[authorizer][nonce] = AuthorizationState.Used;
        emit AuthorizationUsed(authorizer, nonce);
    }

    /**
     * @notice Increase the allowance by a given increment
     * @param spender   Spender's address
     * @param increment Amount of increase in allowance
     * @return True if successful
     */
    function increaseAllowance(address spender, uint256 increment) external returns (bool) {
        _increaseAllowance(msg.sender, spender, increment);
        return true;
    }

    /**
     * @notice Decrease the allowance by a given decrement
     * @param spender   Spender's address
     * @param decrement Amount of decrease in allowance
     * @return True if successful
     */
    function decreaseAllowance(address spender, uint256 decrement) external returns (bool) {
        _decreaseAllowance(msg.sender, spender, decrement);
        return true;
    }

    /**
     * @notice Execute a transfer with a signed authorization
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _transferWithAuthorization(
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Execute a transfer with a signed authorization
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param fee           Fee to be transferred to fee account
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param feeAccount    Account to receive fee
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function transferWithAuthorizationWithFee(
        address from,
        address to,
        uint256 value,
        uint256 fee,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        address feeAccount,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _transferWithAuthorizationWithFee(
            from,
            to,
            value,
            fee,
            validAfter,
            validBefore,
            nonce,
            feeAccount,
            v,
            r,
            s
        );
    }

    /**
     * @notice Update allowance with a signed authorization
     * @param owner         Token owner's address (Authorizer)
     * @param spender       Spender's address
     * @param value         Amount of allowance
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function approveWithAuthorization(
        address owner,
        address spender,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _approveWithAuthorization(
            owner,
            spender,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Increase allowance with a signed authorization
     * @param owner         Token owner's address (Authorizer)
     * @param spender       Spender's address
     * @param increment     Amount of increase in allowance
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function increaseAllowanceWithAuthorization(
        address owner,
        address spender,
        uint256 increment,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _increaseAllowanceWithAuthorization(
            owner,
            spender,
            increment,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Decrease allowance with a signed authorization
     * @param owner         Token owner's address (Authorizer)
     * @param spender       Spender's address
     * @param decrement     Amount of decrease in allowance
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function decreaseAllowanceWithAuthorization(
        address owner,
        address spender,
        uint256 decrement,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _decreaseAllowanceWithAuthorization(
            owner,
            spender,
            decrement,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Attempt to cancel an authorization
     * @dev Works only if the authorization is not yet used.
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _cancelAuthorization(authorizer, nonce, v, r, s);
    }

    /**
     * @notice Internal function to increase the allowance by a given increment
     * @param owner     Token owner's address
     * @param spender   Spender's address
     * @param increment Amount of increase
     */
    function _increaseAllowance(
        address owner,
        address spender,
        uint256 increment
    ) internal {
        _approve(owner, spender, allowed[owner][spender].add(increment));
    }

    /**
     * @notice Internal function to decrease the allowance by a given decrement
     * @param owner     Token owner's address
     * @param spender   Spender's address
     * @param decrement Amount of decrease
     */
    function _decreaseAllowance(
        address owner,
        address spender,
        uint256 decrement
    ) internal {
        _approve(
            owner,
            spender,
            allowed[owner][spender].sub(
                decrement,
                "ERC20: decreased allowance below zero"
            )
        );
    }
}
