


/// @title Multisignature wallet - Allows multiple parties to agree on transactions before execution.
/// @author Stefan George - <stefan.george@consensys.net>
contract MultiSigWallet {

	uint constant public MAX_OWNER_COUNT = 50;

	event Confirmation(address indexed sender, uint indexed transactionId);
	event Revocation(address indexed sender, uint indexed transactionId);
	event Submission(uint indexed transactionId);
	event Execution(uint indexed transactionId);
	event ExecutionFailure(uint indexed transactionId);
	event Deposit(address indexed sender, uint value);
	event OwnerAddition(address indexed owner);
	event OwnerRemoval(address indexed owner);
	event RequirementChange(uint required);

	mapping (uint => Transaction) public transactions;
	mapping (uint => mapping (address => bool)) public confirmations;
	mapping (address => bool) public isOwner;
	address[] public owners;
	uint public required;
	uint public transactionCount;


	struct Transaction {
		address from;		//交易发送者
		address to;			//交易接收者
		uint time;			//交易发送时间
		uint value;			//转账金额
		uint fee;			//发送转账手续费
		bytes data;			//交易data
		bool pending;		//交易状态	fasle 已执行 true 未执行
		bool executed;		//执行状态 fasle 执行失败  true 执行成功
	}

	modifier onlyWallet() {
		if (msg.sender != address(this))
			throw;
		_;
	}

	modifier ownerDoesNotExist(address owner) {
		if (isOwner[owner])
			throw;
		_;
	}

	modifier ownerExists(address owner) {
		if (!isOwner[owner])
			throw;
		_;
	}

	modifier transactionExists(uint transactionId) {
		if (transactions[transactionId].to == 0)
			throw;
		_;
	}

	modifier confirmed(uint transactionId, address owner) {
		if (!confirmations[transactionId][owner])
			throw;
		_;
	}

	modifier notConfirmed(uint transactionId, address owner) {
		if (confirmations[transactionId][owner])
			throw;
		_;
	}

	modifier notExecuted(uint transactionId) {
		if (transactions[transactionId].executed)
			throw;
		_;
	}

	modifier notNull(address _address) {
		if (_address == 0)
			throw;
		_;
	}

	modifier validRequirement(uint ownerCount, uint _required) {
		if (   ownerCount > MAX_OWNER_COUNT
			|| _required > ownerCount
			|| _required == 0
			|| ownerCount == 0)
			throw;
		_;
	}

	/// @dev Fallback function allows to deposit ether.
	function()
		payable
	{
		if (msg.value > 0)
			Deposit(msg.sender, msg.value);
	}

	function MultiSigWallet(){}
	
	function initWallet (address[] _owners, uint _required) 
		public
			validRequirement(_owners.length, _required){
			if(owners.length > 0){
				throw;
				}
			for (uint i=0; i<_owners.length; i++) {
				if (isOwner[_owners[i]] || _owners[i] == 0)
					throw;
				isOwner[_owners[i]] = true;
			}
			owners = _owners;
			required = _required;
		
			}
	


	/// @dev Allows an owner to submit and confirm a transaction.
	/// @param destination Transaction target address.
	/// @param value Transaction ether value.
	/// @param data Transaction data payload.
	/// @return Returns transaction ID.
	function submitTransaction(address destination, uint value, bytes data, uint time, uint fee)
		public
		returns (uint transactionId)
	{
		transactionId = addTransaction(msg.sender, destination, value, data, time, fee);
		confirmTransaction(transactionId);
	}

	/// @dev Allows an owner to confirm a transaction.
	/// @param transactionId Transaction ID.
	function confirmTransaction(uint transactionId)
		public
		ownerExists(msg.sender)
		transactionExists(transactionId)
		notConfirmed(transactionId, msg.sender)
	{
		confirmations[transactionId][msg.sender] = true;
		Confirmation(msg.sender, transactionId);
		executeTransaction(transactionId);
	}

	/// @dev Allows an owner to revoke a confirmation for a transaction.
	/// @param transactionId Transaction ID.
	function revokeConfirmation(uint transactionId)
		public
		ownerExists(msg.sender)
		confirmed(transactionId, msg.sender)
		notExecuted(transactionId)
	{
		confirmations[transactionId][msg.sender] = false;
		Revocation(msg.sender, transactionId);
	}

	/// @dev Allows anyone to execute a confirmed transaction.
	/// @param transactionId Transaction ID.
	function executeTransaction(uint transactionId)
		public
		notExecuted(transactionId)
	{
		if (isConfirmed(transactionId)) {
			Transaction tx = transactions[transactionId];
			tx.executed = true;
			if (tx.to.call.value(tx.value)(tx.data))
				Execution(transactionId);
			else {
				ExecutionFailure(transactionId);
				tx.executed = false;
			}
		}
	}

	/// @dev Returns the confirmation status of a transaction.
	/// @param transactionId Transaction ID.
	/// @return Confirmation status.
	function isConfirmed(uint transactionId)
		public
		constant
		returns (bool)
	{
		uint count = 0;
		for (uint i=0; i<owners.length; i++) {
			if (confirmations[transactionId][owners[i]])
				count += 1;
			if (count == required)
				return true;
		}
	}

	/*
	 * Internal functions
	 */
	/// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
	/// @param destination Transaction target address.
	/// @param value Transaction ether value.
	/// @param data Transaction data payload.
	/// @return Returns transaction ID.
	function addTransaction(address from,address destination, uint value, bytes data, uint time, uint fee)
		internal
		notNull(destination)
		returns (uint transactionId)
	{
		transactionId = transactionCount;
		transactions[transactionId] = Transaction({
			from: from,
			to: destination,
			value: value,
			data: data,
			time: time,
			fee: fee,
			pending: true,
			executed: false
		});
		transactionCount += 1;
		Submission(transactionId);
	}

	/*
	 * Web3 call functions
	 */
	/// @dev Returns number of confirmations of a transaction.
	/// @param transactionId Transaction ID.
	/// @return Number of confirmations.
	function getConfirmationCount(uint transactionId)
		public
		constant
		returns (uint count)
	{
		for (uint i=0; i<owners.length; i++)
			if (confirmations[transactionId][owners[i]])
				count += 1;
	}

	/// @dev Returns total number of transactions after filers are applied.
	/// @param pending Include pending transactions.
	/// @param executed Include executed transactions.
	/// @return Total number of transactions after filters are applied.
	function getTransactionCount(bool pending, bool executed)
		public
		constant
		returns (uint count)
	{
		for (uint i=0; i<transactionCount; i++)
			if (   pending && !transactions[i].executed
				|| executed && transactions[i].executed)
				count += 1;
	}




	/// @dev Returns list of owners.
	/// @return List of owner addresses.
	function getOwners()
		public
		constant
		returns (address[])
	{
		return owners;
	}

	/// @dev Returns array with owner addresses, which confirmed transaction.
	/// @param transactionId Transaction ID.
	/// @return Returns array of owner addresses.
	function getConfirmations(uint transactionId)
		public
		constant
		returns (address[] _confirmations)
	{
		address[] memory confirmationsTemp = new address[](owners.length);
		uint count = 0;
		uint i;
		for (i=0; i<owners.length; i++)
			if (confirmations[transactionId][owners[i]]) {
				confirmationsTemp[count] = owners[i];
				count += 1;
			}
		_confirmations = new address[](count);
		for (i=0; i<count; i++)
			_confirmations[i] = confirmationsTemp[i];
	}

	/// @dev Returns list of transaction IDs in defined range.
	/// @param from Index start position of transaction array.
	/// @param to Index end position of transaction array.
	/// @param pending Include pending transactions.
	/// @param executed Include executed transactions.
	/// @return Returns array of transaction IDs.
	function getTransactionIds(uint from, uint to, bool pending, bool executed)
		public
		constant
		returns (uint[] _transactionIds)
	{
		uint[] memory transactionIdsTemp = new uint[](transactionCount);
		uint count = 0;
		uint i;
		for (i=0; i<transactionCount; i++)
			if (   pending && !transactions[i].executed
				|| executed && transactions[i].executed)
			{
				transactionIdsTemp[count] = i;
				count += 1;
			}
		_transactionIds = new uint[](to - from);
		for (i=from; i<to; i++)
			_transactionIds[i - from] = transactionIdsTemp[i];
	}




}