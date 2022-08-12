// SPDX-License-Identifier: ALEX

pragma solidity ^0.8.0;

import "C:/Users/Alex Nikolic/Desktop/CFCoding/UseCases/shares/openzeppelin-contracts/contracts/security/Pausable.sol";
import "./SnapShotModule.sol"; //holds ERC20
import "./interface/IRuleEngine.sol";
import "./OCF.sol";
import "./RestrictionCodesERC1066.sol";

/**
 * CM01: Attempt to reassign from an original address which is 0x0
 * CM02: Attempt to reassign to a replacement address is 0x0
 * CM03: Attempt to reassign to replacement address which is the same as the original address
 * CM04: Transfer rejected by Rule Engine
 * CM05: Attempt to reassign from an original address which does not have any tokens
 * CM06: Cannot call destroy with owner address contained in parameter
 */

//check CMTA Paper for Modules to be added

contract Stock is SnapShotModule, RestrictionCodes, Pausable {
    error NotOCFcalling();

    event LogReassigned(
        address indexed original,
        address indexed replacement,
        uint256 value
    );

    event LogDestroyed(address[] shareholders);
    event LogRedeemed(uint256 value);
    event LogIssued(uint256 value);

    /**
     * Purpose:
     * This event is emitted when rule engine is changed
     *
     * @param newRuleEngine - new rule engine address
     */
    event LogRuleEngineSet(address indexed newRuleEngine);
    /**
     * Purpose:
     * This event is emitted when the contact information is changed
     *
     * - new contact information
     */
    event LogContactSet(string, string);
    /** Purpose:
     ** tell which address got identified and is eligible to hold shares */
    event gotIdentified(address acc);

    /** Purpose:
     ** emit event when dividends get dpeposited */
    event divdidensDeposited(uint256 time, uint256 amount);
    event dividendsClaimedBy(address claimer);

    address[] public shareholders; //array of shareholders
    mapping(address => bool) private shareholderAddrToBool; //check if shareholder is in array to prevent duplicates in array
    /** @notice the idea is to map the bytes8 identity to a corresponding IBAN or similar off-chain, to have one unique identifier for each account one does hold */
    mapping(address => bytes8) internal identities; //identity needs to be verified before shares can be acquired
    IRuleEngine public ruleEngine; //the ruleEngine that holds the rules, gets assigned through function

    uint256 public dividend; //dividend amount that gets assigned in distributionCreateParameters
    mapping(address => bool) private flaggedShareholders; //shareholders that are identified non-eligible are flagged and excluded from dividend payments

    /**@notice uint256 public distributionTime; @notice possibility to make dividend payments not available straight after the snapshot but to have shareholders to wait until the distributiontime**/

    /** @dev split privileges between 3 roles including the owner of the cotract
     ** @param _snapshotter can schedule, reschedule and unschedule snapshots
     ** @param _operator is the owner of the contract and can reassign, destroy, redeem, issue, setRuleEngine etc.
     ** @param _pauser can pause the trading
     ** @notice by default the owner is covering all roles
     **/
    address private _snapshotter;
    address private _operator;
    address private _pauser;

    OCF public paymentToken; //assign paymentToken if payment should be made on-chain

    /** @param referenceToTerms can be an URL to a termsheet
     * @param contact can be any contactPoint
     */
    struct contactInformation {
        string referenceToTerms;
        string contact;
    }

    contactInformation public prospectus; //prospectus with information

    constructor(
        string memory _name,
        string memory _symbol, //ISIN for example
        string memory _referenceToTerms,
        string memory _contact
    ) ERC20shortened(_name, _symbol) {
        prospectus.referenceToTerms = _referenceToTerms;
        prospectus.contact = _contact;
        _pauser = msg.sender;
        _snapshotter = msg.sender;

        emit LogContactSet(_referenceToTerms, _contact);
    }

    modifier isIdentified(address to) {
        require(identities[to] != "", "Receiver not identified");
        _;
    }

    modifier isSnapshotter() {
        require(msg.sender == hasSnapshotRole(), "not authorized");
        _;
    }

    modifier isPauser() {
        require(msg.sender == hasPauserRole(), "not authorized");
        _;
    }

    /**
     * Purpose
     * Set optional rule engine by owner
     *
     * @param _ruleEngine - the rule engine that will approve/reject transfers
     */
    function setRuleEngine(IRuleEngine _ruleEngine) external onlyOwner {
        ruleEngine = _ruleEngine;
        emit LogRuleEngineSet(address(_ruleEngine));
    }

    function identity(address[] memory shareholder)
        public
        view
        onlyOwner
        returns (bytes8[] memory)
    {
        return _identity(shareholder);
    }

    /**
     * Purpose
     * Retrieve identity of a potential/actual shareholder
     */

    function _identity(address[] memory shareholder)
        internal
        view
        returns (bytes8[] memory)
    {
        bytes8[] memory shareholderIdentities = new bytes8[](
            shareholder.length
        );
        for (uint256 i = 0; i < shareholder.length; i++) {
            shareholderIdentities[i] = identities[shareholder[i]];
        }
        return shareholderIdentities;
    }

    /**
     * Purpose
     * Set identity of a potential/actual shareholder. Can only be called by the potential/actual shareholder himself. Has to be encrypted data.
     *
     * @param _ident - the potential/actual shareholder identity
     */
    function setIdentity(address shareholder, bytes8 _ident)
        external
        onlyOwner
    {
        identities[shareholder] = _ident;
        emit gotIdentified(shareholder);
    }

    function showMyIdentity() public view returns (bytes8) {
        return identities[msg.sender];
    }

    /**
     * Purpose:
     * Issue tokens on the owner address
     *
     * @param _value - amount of newly issued tokens
     */
    function issue(uint256 _value) public onlyOwner {
        _mint(msg.sender, _value);

        emit Transfer(address(0), owner(), _value);
        emit LogIssued(_value);
    }

    /**
     * Purpose:
     * Redeem tokens on the owner address
     *
     * @param _value - amount of redeemed tokens
     */
    function redeem(uint256 _value) public onlyOwner {
        _balances[owner()] = _balances[owner()] - _value;
        _totalSupply = _totalSupply - _value;

        emit Transfer(owner(), address(0), _value);
        emit LogRedeemed(_value);
    }

    /**
     * @dev check if _value token can be transferred from _from to _to
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function canTransfer(
        address _from,
        address _to,
        uint256 _value
    ) public view returns (bool) {
        if (paused()) {
            return false;
        }
        if (identities[_to] == "") {
            return false;
        }
        if (address(ruleEngine) != address(0)) {
            return ruleEngine.validateTransfer(_from, _to, _value);
        }
        return true;
    }

    /**
     * @dev check if _value token can be transferred from _from to _to
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     * @return code of the rejection reason
     */
    function detectTransferRestriction(
        address _from,
        address _to,
        uint256 _value
    ) public view returns (uint8) {
        if (paused()) {
            return 0x42; //Paused
        }
        if (identities[_to] == "") {
            return 0x5A;
        }
        if (address(ruleEngine) != address(0)) {
            return ruleEngine.detectTransferRestriction(_from, _to, _value);
        }
        return 0x51; //Transfer successful
    }

    /**
     * @dev returns the human readable explaination corresponding to the error code returned by detectTransferRestriction
     * @param _restrictionCode The error code returned by detectTransferRestriction
     * @return The human readable explaination corresponding to the error code returned by detectTransferRestriction
     */
    function messageForTransferRestriction(uint8 _restrictionCode)
        external
        view
        returns (string memory)
    {
        if (bytes(codeToText[_restrictionCode]).length != 0) {
            return codeToText[_restrictionCode];
        } else if (address(ruleEngine) != address(0)) {
            return ruleEngine.messageForTransferRestriction(_restrictionCode);
        }
        return "unknown code";
    }

    /**
     * @dev transfer token for a specified address
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     */
    function transfer(address _to, uint256 _value)
        public
        override
        isIdentified(_to)
        whenNotPaused
        returns (bool)
    {
        if (address(ruleEngine) != address(0)) {
            require(
                ruleEngine.validateTransfer(msg.sender, _to, _value),
                "0x50"
            );
        }
        if (!shareholderAddrToBool[_to]) {
            shareholderAddrToBool[_to] = true;
            shareholders.push(_to);
        }
        return super.transfer(_to, _value);
    }

    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public override isIdentified(_to) whenNotPaused returns (bool) {
        if (address(ruleEngine) != address(0)) {
            require(ruleEngine.validateTransfer(_from, _to, _value), "0x50");
        }
        if (!shareholderAddrToBool[_to]) {
            shareholderAddrToBool[_to] = true;
            shareholders.push(_to);
        }
        return super.transferFrom(_from, _to, _value);
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     *
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(address _spender, uint256 _value)
        public
        override
        whenNotPaused
        returns (bool)
    {
        return super.approve(_spender, _value);
    }

    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     *
     * @param _spender The address which will spend the funds.
     * @param _addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address _spender, uint256 _addedValue)
        public
        override
        whenNotPaused
        returns (bool)
    {
        return super.increaseAllowance(_spender, _addedValue);
    }

    /**
     * @dev Decrease the amount of tokens that an owner allowed to a spender.
     *
     * @param _spender The address which will spend the funds.
     * @param _subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseAllowance(address _spender, uint256 _subtractedValue)
        public
        override
        whenNotPaused
        returns (bool)
    {
        return super.decreaseAllowance(_spender, _subtractedValue);
    }

    /**
     * Purpose:
     * To withdraw tokens from the original address and
     * transfer those tokens to the replacement address.
     * Use in cases when e.g. investor loses access to his account.
     *
     * Conditions:
     * Throw error if the `original` address supplied is not a shareholder.
     * Only issuer can execute this function.
     *
     * @param original - original address
     * @param replacement - replacement address
     */
    function reassign(address original, address replacement)
        external
        onlyOwner
        isIdentified(replacement)
        whenNotPaused
    {
        require(original != address(0), "0 address");
        require(replacement != address(0), "0 address");
        require(original != replacement, "original = replacement");
        uint256 originalBalance = _balances[original];
        require(originalBalance != 0, "0x59");
        _balances[replacement] = _balances[replacement] + originalBalance;
        _balances[original] = 0;
        if (!shareholderAddrToBool[replacement]) {
            shareholderAddrToBool[replacement] = true;
            shareholders.push(replacement);
        }
        emit Transfer(original, replacement, originalBalance);
        emit LogReassigned(original, replacement, originalBalance);
    }

    /**
     * Purpose;
     * To destroy issued tokens.
     *
     * Conditions:
     * Only issuer can execute this function.
     *
     * @param shareholder - list of shareholders
     */
    function destroy(address[] calldata shareholder) external onlyOwner {
        for (uint256 i = 0; i < shareholder.length; i++) {
            require(shareholders[i] != owner(), "owner protection");
            uint256 shareholderBalance = _balances[shareholders[i]];
            _balances[owner()] = _balances[owner()] + shareholderBalance;
            _balances[shareholders[i]] = 0;
            emit Transfer(shareholders[i], owner(), shareholderBalance);
        }
        emit LogDestroyed(shareholders);
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function pause() public isPauser {
        _pause();
    }

    function unpause() public isPauser {
        _unpause();
    }

    function getContactInformation()
        public
        view
        returns (string memory, string memory)
    {
        return (prospectus.contact, prospectus.referenceToTerms);
    }

    function setContactInformation(string memory ref, string memory contact)
        external
        onlyOwner
    {
        if (bytes(ref).length != 0) {
            prospectus.referenceToTerms = ref;
        }
        if (bytes(contact).length != 0) {
            prospectus.contact = contact;
        }
        emit LogContactSet(ref, contact);
    }

    /** @notice give Reference to a paymentToken contract
     * @param _paymentToken address of the contract
     */
    function assignPaymentToken(address payable _paymentToken)
        public
        onlyOwner
    {
        paymentToken = OCF(_paymentToken);
    }

    /** @notice is called by payment Token contract when tokens are transferred to the address of THIS contract (it is like buying shares with paymentTokens)
     * @param from defaults to the msg.sender of the transfer function in the payment Token contract
     */

    function tokenFallback(
        address from,
        uint256 value,
        bytes memory /*data*/
    ) public isIdentified(from) {
        if (msg.sender != address(paymentToken)) {
            revert NotOCFcalling();
        }
        if (from != owner()) {
            transferTokenFallback(from, value);

            emit LogIssued(value);
        }
    }

    function transferTokenFallback(address _to, uint256 _value)
        internal
        whenNotPaused
    {
        if (address(ruleEngine) != address(0)) {
            require(ruleEngine.validateTransfer(owner(), _to, _value), "0x50");
        }
        _transfer(owner(), _to, _value);
    }

    /**
     * @notice provide batch transfer for issuer when distributing shares but also for shareholders
     * @dev transfer token for a specified address
     * @param _to The list of addresses to transfer to.
     * @param _value The list of amounts to be transferred.
     */
    function batchTransfer(address[] memory _to, uint256[] memory _value)
        public
        whenNotPaused
    {
        require(_to.length == _value.length, "Not equal receivers and amounts");
        for (uint256 i = 0; i < _to.length; i++) {
            require(identities[_to[i]] != 0, "not identified receiver");
            if (address(ruleEngine) != address(0)) {
                require(
                    ruleEngine.validateTransfer(msg.sender, _to[i], _value[i]),
                    "0x50"
                );
                super.transfer(_to[i], _value[i]);
            }
        }
    }

    /**
     * @dev schedule Snapshots, internal functions are in Snapshot Module
     */
    function scheduleSnapshot(uint256 time) external isSnapshotter {
        _scheduleSnapshot(time);
    }

    /**
     * @dev reschedule Snapshots, -"-
     **/
    function rescheduleSnapshot(uint256 oldTime, uint256 newTime)
        external
        isSnapshotter
        returns (uint256)
    {
        return _rescheduleSnapshot(oldTime, newTime);
    }

    function unscheduleSnapshot(uint256 time)
        external
        isSnapshotter
        returns (uint256)
    {
        return _unscheduleSnapshot(time);
    }

    /**
     * @dev dividends can be paid out as payment tokens via this function, sufficient funds have to be provided within the payment token contract
     * @param _value the entire dividend amount which gets split, should have 18 decimals
    function payDividend(uint256 time, uint256 _value) public onlyOwner {
        uint256 totalDistribution = snapshotTotalSupply(time);
        for (uint256 i = 0; i < shareholders.length; i++) {
            uint256 snapshotTokens = snapshotBalanceOf(time, shareholders[i]);
            uint256 dividend = (_value * snapshotTokens) / totalDistribution;
            paymentToken.transfer(shareholders[i], dividend);
        }
    }
     **/

    /** ==================================================== DISTRIBUTION OF DIVIDENDS ======================================================== */

    // makes SnapShot and leads mapping, updates dividend to be paid
    function distributionSetEligibility(address[] memory _flaggedShareholders)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < _flaggedShareholders.length; i++) {
            flaggedShareholders[_flaggedShareholders[i]] = true;
        }
    }

    /**
     * @dev call to make allowances and prepare for shareholders to claim their tokens
     * @param amount should be 18 decimals and represents entire dividend amount */
    function distributionCreateParameters(uint256 amount) external onlyOwner {
        pause();
        for (uint256 i = 0; i < shareholders.length; i++) {
            if (!flaggedShareholders[shareholders[i]]) {
                uint256 res = (amount * balanceOf(shareholders[i])) /
                    totalSupply();
                distributionSetDeposit(shareholders[i], res);
            }
        }
        dividend = amount;
        emit divdidensDeposited(block.timestamp, amount);
    }

    /** @notice make transferfrom allowance in ocf contract
     * kept public to allow for extraordinary allowances due to off chain storage of shares*/
    function distributionSetDeposit(address shareholder, uint256 amount)
        public
        onlyOwner
    {
        paymentToken.approve(shareholder, amount);
    }

    /** @dev give shareholders the opportnitzy to retrieve their funds that were approved in the previous function */
    function distributionClaimDeposit() external returns (bool) {
        uint256 allowed = paymentToken.allowance(address(this), msg.sender);
        bool success = paymentToken.transfer(msg.sender, allowed);
        paymentToken.decreaseAllowance(msg.sender, allowed);
        emit dividendsClaimedBy(msg.sender);
        return success;
    }

    /** ======================================= AUTHORIZATION MODULE ============================================= **/

    /** @dev Grant roles to accounts */
    function grantSnapshotRole(address acc) external onlyOwner {
        _snapshotter = acc;
    }

    function grantOperatorRole(address acc) external onlyOwner {
        transferOwnership(acc);
    }

    function grantPauserRole(address acc) external onlyOwner {
        _pauser = acc;
    }

    /** @dev revoke roles from accounts
     ** owner cannot be revoked for security **/
    function revokeSnapshotRole() external onlyOwner {
        _snapshotter = address(0);
    }

    function revokePauserRole() external onlyOwner {
        _pauser = address(0);
    }

    /** @dev show addresses that have role */

    function hasSnapshotRole() public view onlyOwner returns (address) {
        return _snapshotter;
    }

    function hasOperatorRole() public view onlyOwner returns (address) {
        return owner();
    }

    function hasPauserRole() public view onlyOwner returns (address) {
        return _pauser;
    }
}
