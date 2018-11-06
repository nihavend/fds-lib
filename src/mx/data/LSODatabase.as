package mx.data
{
   import flash.events.EventDispatcher;
   import mx.data.events.DatabaseStatusEvent;
   import mx.data.events.DatabaseUpdateEvent;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.rpc.AsyncDispatcher;
   import mx.utils.HashUtil;
   import mx.utils.UIDUtil;
   
   [ExcludeClass]
   public class LSODatabase extends EventDispatcher implements IDatabase
   {
      
      private static var log:ILogger = Log.getLogger("mx.data.LSODataStore");
       
      
      private var dbStore:LSODBStore;
      
      private var _shared:Boolean;
      
      private var _debugId:String;
      
      public function LSODatabase(shared:Boolean = false)
      {
         super();
         this._shared = shared;
      }
      
      public function get autoCommit() : Boolean
      {
         if(this.connected)
         {
            return this.dbStore.autoCommit;
         }
         return false;
      }
      
      public function get connected() : Boolean
      {
         return this.dbStore != null;
      }
      
      public function get empty() : Boolean
      {
         this.checkConnected();
         return this.dbStore.empty;
      }
      
      public function get inTransaction() : Boolean
      {
         return this.dbStore != null?Boolean(this.dbStore.inTransaction):Boolean(false);
      }
      
      public function encryptionSupported() : Boolean
      {
         return false;
      }
      
      public function get encryptLocalCache() : Boolean
      {
         return false;
      }
      
      public function set encryptLocalCache(enabled:Boolean) : void
      {
         if(enabled)
         {
            throw new Error("Encryption is not supported for local shared objects.");
         }
      }
      
      public function get shared() : Boolean
      {
         return this._shared;
      }
      
      public function begin(option:String = null) : void
      {
         this.checkConnected();
         this.dbStore.begin(option);
         if(Log.isDebug())
         {
            this._debugId = UIDUtil.createUID();
            log.debug("LSODatabase begin(" + option + "): " + this._debugId);
         }
      }
      
      public function close() : void
      {
         var dbsl:LSODBStore = null;
         var statusHandler:Function = null;
         if(Log.isDebug())
         {
            log.debug("LSODatabase close(): " + this._debugId);
         }
         dbsl = this.dbStore;
         statusHandler = function(event:DatabaseStatusEvent):void
         {
            dbsl.removeEventListener(DatabaseStatusEvent.STATUS,statusHandler);
            dispatchEvent(event);
         };
         if(this.dbStore != null)
         {
            this.dbStore.removeEventListener(DatabaseStatusEvent.STATUS,dispatchEvent);
            this.dbStore.removeEventListener(DatabaseUpdateEvent.UPDATE,dispatchEvent);
            this.dbStore.addEventListener(DatabaseStatusEvent.STATUS,statusHandler);
            this.dbStore.close();
            LSODBStore.releaseStore(this.dbStore);
            this.dbStore = null;
         }
         else
         {
            new AsyncDispatcher(this.dispatchStatusEvent,["Client.Close.Success","status"],1);
         }
      }
      
      public function commit() : void
      {
         this.checkConnected();
         this.dbStore.commit();
      }
      
      public function connect(value:Object) : void
      {
         var name:String = value as String;
         if(this.dbStore == null)
         {
            try
            {
               name = HashUtil.apHash(name).toString();
               this.dbStore = LSODBStore.getStore(name,!!this._shared?"/_S_":null);
               this.dbStore.addEventListener(DatabaseStatusEvent.STATUS,dispatchEvent);
               this.dbStore.addEventListener(DatabaseUpdateEvent.UPDATE,dispatchEvent);
               this.dbStore.connect();
               if(Log.isDebug())
               {
                  log.debug("LSODatabase connected(): " + this._debugId);
               }
            }
            catch(e:Error)
            {
               new AsyncDispatcher(dispatchStatusEvent,["Client.Connect.Failed","error",e.message],1);
               dbStore = null;
            }
         }
         else if(this.dbStore.name != name)
         {
            new AsyncDispatcher(this.dispatchStatusEvent,["Client.Connect.Failed","error","Database must be closed before this operation can be performed."],1);
         }
         else
         {
            new AsyncDispatcher(this.dispatchStatusEvent,["Client.Connect.Success","status"],1);
         }
      }
      
      public function drop() : void
      {
         this.checkConnected();
         this.dbStore.drop();
      }
      
      public function getConnection() : Object
      {
         return null;
      }
      
      public function getCollection(name:String = null) : IDatabaseCollection
      {
         this.checkConnected();
         return this.dbStore.getCollection(name);
      }
      
      public function rollback() : void
      {
         this.checkConnected();
         this.dbStore.rollback();
      }
      
      private function checkConnected() : void
      {
         if(this.dbStore == null)
         {
            throw new Error("Database must be connected to perform this operation.");
         }
      }
      
      private function dispatchStatusEvent(code:String, level:String, details:String = "") : void
      {
         var event:DatabaseStatusEvent = new DatabaseStatusEvent(DatabaseStatusEvent.STATUS);
         event.code = code;
         event.level = level;
         event.details = details;
         dispatchEvent(event);
      }
   }
}

import flash.events.AsyncErrorEvent;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.NetStatusEvent;
import flash.events.StatusEvent;
import flash.events.TimerEvent;
import flash.net.LocalConnection;
import flash.net.SharedObject;
import flash.net.SharedObjectFlushStatus;
import flash.net.registerClassAlias;
import flash.utils.Timer;
import mx.core.mx_internal;
import mx.data.IDatabaseCollection;
import mx.data.events.DatabaseStatusEvent;
import mx.data.events.DatabaseUpdateEvent;
import mx.logging.ILogger;
import mx.logging.Log;
import mx.rpc.AsyncDispatcher;
import mx.utils.ObjectUtil;
import mx.utils.UIDUtil;

class LSODBStore extends EventDispatcher
{
   
   public static const EXCLUSIVE:String = "exclusive";
   
   public static const DEFERRED:String = "deferred";
   
   public static const IMMEDIATE:String = "immediate";
   
   private static const JOURNAL_ENTRIES:String = "_jrnl_";
   
   private static const COLLECTION_BACKUP:String = "_colbck_";
   
   private static const COLLECTION_ENTRIES:String = "_colnames_";
   
   private static var storePool:Object = {};
   
   private static var log:ILogger = Log.getLogger("mx.data.LSODataStore");
   
   private static const MAX_CONNECT_ATTEMPTS:int = 3;
    
   
   private var _autoCommit:Boolean = true;
   
   private var clientId:String;
   
   private var connectionName:String;
   
   private var collections:Object;
   
   private var _empty:Boolean = true;
   
   private var heartbeat:Timer;
   
   private var connectAttempts:int;
   
   private var inbound:LocalConnection;
   
   private var lock:LocalConnection;
   
   private var locks:uint;
   
   private var journal:SharedObject;
   
   private var _name:String;
   
   private var outbound:LocalConnection;
   
   private var path:String;
   
   private var pulseRead:Boolean;
   
   private var refs:uint = 0;
   
   private var subscribers:Object;
   
   function LSODBStore(name:String, path:String)
   {
      this.collections = {};
      this.subscribers = {
         "clients":{},
         "count":0
      };
      super();
      this.path = path;
      this._name = name;
      registerClassAlias("JournalEntry",JournalEntry);
   }
   
   public static function getStore(name:String, path:String) : LSODBStore
   {
      var store:LSODBStore = storePool[name];
      if(store == null)
      {
         store = new LSODBStore(name,path);
         storePool[name] = store;
      }
      store.refs++;
      return store;
   }
   
   public static function releaseStore(store:LSODBStore) : void
   {
      store.refs--;
      if(store.refs == 0)
      {
         delete storePool[store.name];
      }
   }
   
   public function get autoCommit() : Boolean
   {
      return this._autoCommit;
   }
   
   public function get connected() : Boolean
   {
      return this.outbound != null;
   }
   
   public function get empty() : Boolean
   {
      return this._empty;
   }
   
   public function get inTransaction() : Boolean
   {
      return this.lock != null;
   }
   
   public function get name() : String
   {
      return this._name;
   }
   
   public function begin(option:String = null) : void
   {
      if(this.lock != null)
      {
         if(Log.isDebug())
         {
            log.debug("Attempt to begin a new transaction with a lock in place on LSOStore: " + this.name);
         }
         throw new Error("Nested transactions are not supported.");
      }
      this.acquireLock();
      if(this.clientId == null)
      {
         this._autoCommit = false;
      }
      else
      {
         this.outbound.send(this.connectionName,"clientBeginRequestEvent",this.clientId,option);
      }
   }
   
   public function close() : void
   {
      this.internalClose();
   }
   
   public function connect() : void
   {
      var outError:Boolean = false;
      var errMsg:String = null;
      if(this.outbound == null)
      {
         this.outbound = new LocalConnection();
         this.outbound.addEventListener(StatusEvent.STATUS,this.connectionStatusHandler);
         this.outbound.addEventListener(AsyncErrorEvent.ASYNC_ERROR,this.serverConnectionErrorHandler);
         this.connectionName = "mx.data." + this.name;
         outError = true;
         errMsg = null;
         try
         {
            this.outbound.client = this;
            this.outbound.connect(this.connectionName);
            outError = false;
            this.journal = SharedObject.getLocal(this.name,this.path);
            this._empty = this.journal.data[LSODBStore.COLLECTION_ENTRIES] == null;
            if(!this._empty && this.journalEntries.length > 0)
            {
               this.restoreFailedWrite();
            }
            this.clientId = null;
         }
         catch(e:Error)
         {
            if(outError)
            {
               if(inbound == null)
               {
                  clientId = UIDUtil.createUID();
                  inbound = new LocalConnection();
                  inbound.addEventListener(StatusEvent.STATUS,serverConnectionStatusHandler);
                  inbound.addEventListener(AsyncErrorEvent.ASYNC_ERROR,serverConnectionErrorHandler);
                  try
                  {
                     inbound.client = this;
                     inbound.connect(clientId);
                     if(Log.isDebug())
                     {
                        log.debug("Database instance is remote {0}",Boolean(journal)?"server":"client");
                     }
                  }
                  catch(e:Error)
                  {
                     inbound = null;
                     errMsg = e.message;
                  }
               }
               if(inbound != null)
               {
                  outbound.send(connectionName,"clientSubscribeEvent",clientId);
               }
               else
               {
                  errMsg = e.message;
               }
            }
            else
            {
               throw e;
            }
         }
      }
      if(Log.isInfo())
      {
         log.info("Database instance is local {0}",Boolean(this.journal)?"server":"client");
      }
      if(errMsg == null)
      {
         new AsyncDispatcher(this.dispatchStatusEvent,["Client.Connect.Success","status"],1);
      }
      else
      {
         new AsyncDispatcher(this.dispatchStatusEvent,["Client.Connect.Failed","error",errMsg],1);
      }
   }
   
   public function commit() : void
   {
      this.checkConnected();
      if(this.clientId == null)
      {
         this.internalCommit(null);
      }
      else
      {
         this.outbound.send(this.connectionName,"clientCommitRequestEvent",this.clientId);
      }
   }
   
   public function getCollection(name:String) : IDatabaseCollection
   {
      this.checkConnected();
      var result:LSODBStoreCollection = this.collections[name];
      if(result == null)
      {
         result = new LSODBStoreCollection(this,name,this.path,this.clientId != null);
         this.collections[name] = result;
         if(this.clientId == null)
         {
            this.allCollections[name] = 1;
            this._empty = false;
         }
         else
         {
            this.outbound.send(this.connectionName,"clientGetCollectionData",this.clientId,result.name);
         }
      }
      return result;
   }
   
   public function drop() : void
   {
      var colNames:Object = null;
      var collection:LSODBStoreCollection = null;
      var name:String = null;
      try
      {
         this.acquireLock();
         if(!this._empty)
         {
            if(this.journal != null)
            {
               colNames = this.allCollections;
               for(name in colNames)
               {
                  collection = LSODBStoreCollection(this.getCollection(name));
                  collection.drop();
               }
               this.clearJournal();
               this.allCollections = {};
               this.journal.clear();
               this._empty = true;
               this.releaseCollections();
               this.sendDropEventToClients();
               new AsyncDispatcher(this.dispatchStatusEvent,["Client.Drop.Success","status"],1);
            }
            else
            {
               this.outbound.send(this.clientId,"clientDropRequestEvent");
            }
         }
      }
      finally
      {
         this.releaseLock(true);
      }
   }
   
   public function internalPut(key:Object, value:Object, kind:String, col:LSODBStoreCollection) : void
   {
      this.checkConnected();
      this.sendUpdateEvent(col.name,key,value,this.clientId,kind);
      this.dispatchUpdateEvent(col.name,key,kind);
   }
   
   public function internalRemove(key:Object, col:LSODBStoreCollection) : void
   {
      this.checkConnected();
      this.sendUpdateEvent(col.name,key,null,this.clientId,DatabaseUpdateEvent.DELETE);
      this.dispatchUpdateEvent(col.name,key,DatabaseUpdateEvent.DELETE);
   }
   
   public function internalRemoveAll(col:LSODBStoreCollection) : void
   {
      this.checkConnected();
   }
   
   public function rollback() : void
   {
      this.checkConnected();
      this.internalRollback();
      this.dispatchStatusEvent("Client.Rollback.Success","status");
   }
   
   public function acquireLock() : void
   {
      this.checkConnected();
      if(this.lock == null)
      {
         this.lock = new LocalConnection();
         this.lock.addEventListener(StatusEvent.STATUS,this.logLockEvent);
         this.lock.addEventListener(AsyncErrorEvent.ASYNC_ERROR,this.logLockEvent);
         try
         {
            this.lock.connect(this.connectionName + "_mx_dbstore_exclusive_");
            if(Log.isDebug())
            {
               log.debug("dbStore locked: " + this.name);
            }
         }
         catch(e:Error)
         {
            lock = null;
            throw new Error("Couldn\'t acquire lock. Operation failed.");
         }
      }
      this.locks++;
   }
   
   public function clientBeginRequestEvent(clientId:String, option:String) : void
   {
      if(Log.isDebug())
      {
         log.debug("Client {0} requested transaction begin.",clientId);
      }
      this._autoCommit = false;
   }
   
   public function clientCheckPulseEvent(clientId:String) : void
   {
      var client:LocalConnection = null;
      var isSubscriber:Boolean = false;
      if(Log.isDebug())
      {
         client = this.subscribers.clients[clientId];
         isSubscriber = client != null;
         log.debug("Client {0} checked server pulse and {1}",clientId,!!isSubscriber?"is subscribed.":"was not subscribed.");
      }
      this.clientSubscribeEvent(clientId);
   }
   
   public function clientCommitRequestEvent(clientId:String) : void
   {
      if(Log.isDebug())
      {
         log.debug("Client {0} requested transaction commit.",clientId);
      }
      this.internalCommit(clientId);
   }
   
   public function clientDropRequestEvent(clientId:String) : void
   {
      if(Log.isDebug())
      {
         log.debug("Client {0} requested drop.",clientId);
      }
      this.drop();
   }
   
   public function clientGetCollectionData(clientId:String, collection:String) : void
   {
      var client:LocalConnection = this.subscribers.clients[clientId];
      var col:LSODBStoreCollection = LSODBStoreCollection(this.getCollection(collection));
      client.send(clientId,"serverGetCollectionDataAckEvent",collection,col.mx_internal::data);
   }
   
   public function clientRollbackEvent(clientId:String) : void
   {
      if(Log.isDebug())
      {
         log.debug("Client {0} requested transaction commit.",clientId);
      }
      this.rollback();
   }
   
   public function clientSubscribeEvent(clientId:String) : void
   {
      var csHandler:Function = null;
      var client:LocalConnection = this.subscribers.clients[clientId];
      if(client == null)
      {
         client = new LocalConnection();
         try
         {
            csHandler = function clientSendStatusHandler(event:StatusEvent):void
            {
               if(event.level == "error")
               {
                  clientUnsubscribeEvent(clientId);
                  EventDispatcher(event.target).removeEventListener(StatusEvent.STATUS,csHandler);
               }
            };
            client.addEventListener(StatusEvent.STATUS,csHandler);
            client.send(clientId,"serverSubscribeAckEvent",this._empty);
         }
         catch(ignore:Error)
         {
         }
         this.subscribers.clients[clientId] = client;
         this.subscribers.count++;
      }
   }
   
   public function clientUnsubscribeEvent(clientId:String) : void
   {
      if(Log.isDebug())
      {
         log.debug("Removing client subscriber {0}",clientId);
      }
      delete this.subscribers.clients[clientId];
      this.subscribers.count--;
   }
   
   public function clientUpdateEvent(collection:String, clientId:String, key:Object, value:Object, kind:String) : void
   {
      this.addJournalEntry(collection,key,value,kind);
      if(this.autoCommit)
      {
         this.internalCommit(clientId);
      }
   }
   
   public function releaseLock(all:Boolean = false) : void
   {
      if(this.lock != null)
      {
         this.locks--;
         if(this.locks == 0 || all)
         {
            this.lock.close();
            this.lock = null;
            this.locks = 0;
            if(Log.isDebug())
            {
               log.debug("dbStore lock released: " + this.name);
            }
         }
      }
   }
   
   public function serverCommitFailedEvent() : void
   {
      this.releaseLock();
      this.dispatchStatusEvent("Client.Commit.Failed","error");
   }
   
   public function serverCommitSuccessEvent() : void
   {
      this.releaseLock();
      this.dispatchStatusEvent("Client.Commit.Success","status");
   }
   
   public function serverDataEvent(collection:String, key:Object, value:Object, kind:String) : void
   {
      var oldVal:Object = null;
      var col:LSODBStoreCollection = this.collections[collection];
      if(col)
      {
         oldVal = col.mx_internal::data[key];
         if(kind == DatabaseUpdateEvent.DELETE)
         {
            delete col.mx_internal::data[key];
         }
         else
         {
            col.mx_internal::data[key] = value;
         }
         this.dispatchUpdateEvent(collection,key,kind);
      }
   }
   
   public function serverDropEvent() : void
   {
      var i:* = null;
      for(i in this.collections)
      {
         this.collections[i].drop();
      }
      this.dispatchStatusEvent("Client.Drop.Success","status");
   }
   
   public function serverGetCollectionDataAckEvent(collection:String, data:Object) : void
   {
      var col:LSODBStoreCollection = this.collections[collection];
      if(col)
      {
         col.mx_internal::data = data;
      }
   }
   
   public function serverStopEvent() : void
   {
      this.internalClose(false);
      this.connect();
   }
   
   public function serverSubscribeAckEvent(empty:Boolean) : void
   {
      this._empty = empty;
      this.pulseCheck(true);
   }
   
   private function get allCollections() : Object
   {
      if(this.journal != null)
      {
         if(this.journal.data[LSODBStore.COLLECTION_ENTRIES] == null)
         {
            this.journal.data[LSODBStore.COLLECTION_ENTRIES] = {};
            this._empty = false;
         }
         return this.journal.data[LSODBStore.COLLECTION_ENTRIES];
      }
      return null;
   }
   
   private function set allCollections(value:Object) : void
   {
      this.journal.data[LSODBStore.COLLECTION_ENTRIES] = value;
   }
   
   private function get journalEntries() : Array
   {
      if(this.journal != null)
      {
         if(this.journal.data[LSODBStore.JOURNAL_ENTRIES] == null)
         {
            this.journal.data[LSODBStore.JOURNAL_ENTRIES] = [];
         }
         return this.journal.data[LSODBStore.JOURNAL_ENTRIES] as Array;
      }
      return null;
   }
   
   private function addJournalEntry(collection:String, key:Object, value:Object, kind:String) : void
   {
      var jrnlEntry:JournalEntry = new JournalEntry();
      jrnlEntry.collection = collection;
      jrnlEntry.data = value;
      jrnlEntry.key = key;
      jrnlEntry.isDelete = kind == DatabaseUpdateEvent.DELETE;
      this.journalEntries.push(jrnlEntry);
      this._empty = false;
   }
   
   private function applyJournal() : Array
   {
      var entry:JournalEntry = null;
      var collection:LSODBStoreCollection = null;
      var i:uint = 0;
      var j:* = null;
      var result:Array = [];
      var entries:Array = this.journalEntries;
      var collectionsUpdated:Object = {};
      if(entries != null)
      {
         for(i = 0; i < entries.length; i++)
         {
            entry = entries[i];
            collection = LSODBStoreCollection(this.getCollection(entry.collection));
            if(entry.isDelete)
            {
               delete collection.mx_internal::data[entry.key];
            }
            else
            {
               collection.mx_internal::data[entry.key] = entry.data;
            }
            collectionsUpdated[collection.name] = collection;
         }
         for(j in collectionsUpdated)
         {
            collection = collectionsUpdated[j];
            collection.mx_internal::commit();
            result.push(collection);
         }
      }
      return result;
   }
   
   private function checkConnected() : void
   {
      if(!this.connected)
      {
         throw new Error("Database must be connected to perform this operation.");
      }
   }
   
   private function clearJournal() : void
   {
      this.journal.data[LSODBStore.JOURNAL_ENTRIES] = [];
      this.journal.data[LSODBStore.COLLECTION_BACKUP] = null;
      this._empty = false;
   }
   
   private function connectionStatusHandler(event:StatusEvent) : void
   {
      if(event.level == "error" && !this.pulseRead)
      {
         if(Log.isDebug())
         {
            log.error("Server is down, attempting reconnect.");
         }
         this.internalClose(false);
         this.connect();
      }
      else if(event.level == "status" && !this.pulseRead)
      {
         this.pulseRead = true;
      }
   }
   
   private function collectionsFlushFailed(errorHandler:Function, list:Array) : void
   {
      var collection:LSODBStoreCollection = null;
      var backupColData:Object = this.journal.data[LSODBStore.COLLECTION_BACKUP];
      for(var i:uint = 0; i < list.length; i++)
      {
         collection = list[i];
         collection.drop();
         if(backupColData != null)
         {
            collection.mx_internal::restore(backupColData[collection.name]);
         }
         collection.mx_internal::flush();
      }
      this.clearJournal();
      errorHandler();
   }
   
   private function collectionSaved(collection:LSODBStoreCollection, pending:Array, saved:Array, successHandler:Function, errorHandler:Function) : void
   {
      if(saved == null)
      {
         saved = [];
      }
      saved.push(collection);
      if(pending.length > 0)
      {
         this.flushCollections(pending,successHandler,errorHandler,saved);
      }
      else
      {
         successHandler();
      }
   }
   
   private function dispatchStatusEvent(code:String, level:String, details:String = null) : void
   {
      dispatchEvent(new DatabaseStatusEvent(null,false,false,code,level,details));
   }
   
   private function dispatchUpdateEvent(collection:String, key:Object, kind:String) : void
   {
      var event:DatabaseUpdateEvent = new DatabaseUpdateEvent(null,false,false,collection,key,kind);
      if(hasEventListener(DatabaseUpdateEvent.UPDATE))
      {
         dispatchEvent(event);
      }
      var col:LSODBStoreCollection = this.collections[collection];
      if(col)
      {
         col.dispatchEvent(event);
      }
   }
   
   private function flush(successHandler:Function, errorHandler:Function) : void
   {
      var journalFlushedHandler:Function = function():void
      {
         flushCollections(applyJournal(),successHandler,errorHandler);
      };
      var journalFailedHandler:Function = function():void
      {
         internalRollback();
         errorHandler();
      };
      this.flushJournal(journalFlushedHandler,journalFailedHandler);
   }
   
   private function flushCollections(pending:Array, successHandler:Function, errorHandler:Function, saved:Array = null) : void
   {
      var collection:LSODBStoreCollection = null;
      var colStatusHandler:Function = null;
      collection = pending.pop();
      colStatusHandler = function(event:NetStatusEvent):void
      {
         var info:Object = null;
         collection.removeEventListener(NetStatusEvent.NET_STATUS,colStatusHandler);
         if(event.info != null)
         {
            info = event.info;
            if(info.level == "error")
            {
               collectionsFlushFailed(errorHandler,saved);
            }
            else if(info.level == "status")
            {
               collectionSaved(collection,pending,saved,successHandler,errorHandler);
            }
         }
      };
      if(collection != null)
      {
         if(collection.mx_internal::flush() == SharedObjectFlushStatus.FLUSHED)
         {
            this.collectionSaved(collection,pending,saved,successHandler,errorHandler);
         }
         else
         {
            collection.addEventListener(NetStatusEvent.NET_STATUS,colStatusHandler);
         }
      }
      else
      {
         successHandler();
      }
   }
   
   private function flushJournal(successHandler:Function, errorHandler:Function) : void
   {
      var jrnlStatusHandler:Function = null;
      jrnlStatusHandler = function(event:NetStatusEvent):void
      {
         var info:Object = null;
         journal.removeEventListener(NetStatusEvent.NET_STATUS,jrnlStatusHandler);
         if(event.info != null)
         {
            info = event.info;
            if(info.level == "error")
            {
               if(errorHandler != null)
               {
                  errorHandler();
               }
            }
            else if(info.level == "status")
            {
               successHandler();
            }
         }
      };
      if(this.journalEntries != null)
      {
         if(this.journal.flush() == SharedObjectFlushStatus.FLUSHED)
         {
            successHandler();
         }
         else
         {
            this.journal.addEventListener(NetStatusEvent.NET_STATUS,jrnlStatusHandler);
         }
      }
      else
      {
         successHandler();
      }
   }
   
   private function internalClose(unsubscribe:Boolean = true) : void
   {
      if(this.inbound != null)
      {
         this.inbound.close();
         this.inbound = null;
      }
      if(this.outbound != null)
      {
         if(this.clientId != null)
         {
            this.pulseCheck(false);
            if(unsubscribe)
            {
               this.outbound.send(this.connectionName,"clientUnsubscribeEvent",this.clientId);
            }
         }
         else
         {
            this.outbound.close();
            this.resetSubscribers();
         }
         this.outbound = null;
      }
      this.journal = null;
      this.releaseCollections();
      new AsyncDispatcher(dispatchEvent,[new DatabaseStatusEvent(null,false,false,"Client.Close.Success","status")],1);
   }
   
   private function internalCommit(senderId:String) : void
   {
      if(this.journalEntries == null || this.journalEntries.length == 0)
      {
         this.releaseLock();
         this._autoCommit = true;
         new AsyncDispatcher(this.dispatchStatusEvent,["Client.Commit.Success","status","Nothing to commit."],1);
         return;
      }
      var dispatchSuccess:Function = function():void
      {
         new AsyncDispatcher(dispatchStatusEvent,["Client.Commit.Success","status"],1);
      };
      var success:Function = function():void
      {
         var jrnlEntry:JournalEntry = null;
         var i:uint = 0;
         releaseLock();
         _autoCommit = true;
         var entries:Array = journalEntries;
         if(entries != null)
         {
            for(i = 0; i < entries.length; i++)
            {
               jrnlEntry = entries[i];
               sendUpdateToClients(jrnlEntry.collection,senderId,jrnlEntry.key,jrnlEntry.data,DatabaseUpdateEvent.UPDATE);
            }
            clearJournal();
            if(senderId == null)
            {
               dispatchSuccess();
            }
            else
            {
               sendCommitSuccessToClient(senderId);
            }
         }
      };
      var error:Function = function():void
      {
         rollback();
         if(senderId == null)
         {
            dispatchStatusEvent("Client.Commit.Failed","status");
         }
         else
         {
            sendCommitFailedToClient(senderId);
         }
      };
      this.flush(success,error);
   }
   
   private function internalRollback() : void
   {
      var collection:LSODBStoreCollection = null;
      var modCollections:Object = null;
      var jrnlEntry:JournalEntry = null;
      var i:uint = 0;
      var j:* = null;
      this.releaseLock();
      var entries:Array = this.journalEntries;
      if(entries != null && entries.length > 0)
      {
         modCollections = {};
         for(i = 0; i < entries.length; i++)
         {
            jrnlEntry = entries[i];
            modCollections[jrnlEntry.collection] = this.collections[jrnlEntry.collection];
         }
         for(j in modCollections)
         {
            modCollections[j].mx_internal::rollback();
         }
         this._autoCommit = true;
         this.clearJournal();
      }
   }
   
   private function logLockEvent(event:Event) : void
   {
      if(event is StatusEvent && StatusEvent(event).level == "error" || event is AsyncErrorEvent)
      {
         if(Log.isError())
         {
            log.error("An error occurred acquiring a lock. {0}",ObjectUtil.toString(event,null,["target","currentTarget"]));
         }
      }
      else if(Log.isDebug())
      {
         log.debug("Lock event {0}",ObjectUtil.toString(event,null,["target","currentTarget"]));
      }
   }
   
   private function pulseCheck(run:Boolean) : void
   {
      if(run && this.heartbeat == null)
      {
         this.heartbeat = new Timer(5000);
         this.heartbeat.addEventListener(TimerEvent.TIMER,this.timerHandler);
         this.heartbeat.start();
      }
      else if(!run && this.heartbeat != null)
      {
         this.heartbeat.stop();
         this.heartbeat.removeEventListener(TimerEvent.TIMER,this.timerHandler);
         this.heartbeat = null;
      }
   }
   
   private function releaseCollections() : void
   {
      var collection:LSODBStoreCollection = null;
      var i:* = null;
      for(i in this.collections)
      {
         collection = this.collections[i];
         collection.mx_internal::release();
      }
      this.collections = {};
   }
   
   private function restoreFailedWrite() : void
   {
      if(Log.isDebug())
      {
         log.debug("Restoring from failed write.");
      }
      this.clearJournal();
   }
   
   private function resetSubscribers() : void
   {
      var client:LocalConnection = null;
      var i:* = null;
      var clients:Object = this.subscribers.clients;
      for(i in clients)
      {
         client = clients[i];
         client.send(i,"serverStopEvent");
         delete clients[i];
      }
      this.subscribers.count = 0;
   }
   
   private function sendDropEventToClients() : void
   {
      var client:LocalConnection = null;
      var i:* = null;
      var clients:Object = this.subscribers.clients;
      for(i in clients)
      {
         client = clients[i];
         client.send(i,"serverDropEvent");
      }
   }
   
   private function sendUpdateEvent(collection:String, key:Object, value:Object, senderId:String, kind:String) : void
   {
      if(this.clientId == null)
      {
         this.addJournalEntry(collection,key,value,kind);
         if(this.autoCommit)
         {
            this.internalCommit(null);
         }
      }
      else
      {
         this.outbound.send(this.connectionName,"clientUpdateEvent",collection,this.clientId,key,value,kind);
      }
   }
   
   private function sendUpdateToClients(collection:String, senderId:String, key:Object, value:Object, kind:String) : void
   {
      var client:LocalConnection = null;
      var i:* = null;
      var clients:Object = this.subscribers.clients;
      for(i in clients)
      {
         if(senderId == null || i != senderId)
         {
            client = clients[i];
            client.send(i,"serverDataEvent",collection,key,value,kind);
         }
      }
   }
   
   private function sendCommitFailedToClient(clientId:String) : void
   {
      var client:LocalConnection = this.subscribers.clients[clientId];
      if(client != null)
      {
         client.send(clientId,"serverCommitFailedEvent");
      }
   }
   
   private function sendCommitSuccessToClient(clientId:String) : void
   {
      var client:LocalConnection = this.subscribers.clients[clientId];
      if(client != null)
      {
         client.send(clientId,"serverCommitSuccessEvent");
      }
   }
   
   private function serverConnectionStatusHandler(event:StatusEvent) : void
   {
      if(event.level == "error")
      {
         if(Log.isWarn())
         {
            log.warn("Could not connect to server \'{0}\'. Attempting reconnect number {1}.",event.code,this.connectAttempts);
         }
         if(this.connectAttempts < MAX_CONNECT_ATTEMPTS)
         {
            this.connectAttempts++;
            this.internalClose(false);
            this.connect();
         }
         else
         {
            this.connectAttempts = 0;
            this.dispatchStatusEvent("Client.Connect.Failed","error");
         }
      }
   }
   
   private function serverConnectionErrorHandler(event:AsyncErrorEvent) : void
   {
      if(Log.isError())
      {
         log.error("Could not connect to server \'{0}\'. Attempting reconnect number {1}.",event.text,this.connectAttempts);
      }
      if(this.connectAttempts < MAX_CONNECT_ATTEMPTS)
      {
         this.connectAttempts++;
         this.internalClose(false);
         this.connect();
      }
      else
      {
         this.connectAttempts = 0;
         this.dispatchStatusEvent("Client.Connect.Failed","error",event.text);
      }
   }
   
   private function timerHandler(event:TimerEvent) : void
   {
      if(Log.isDebug())
      {
         log.debug("Checking the server heartbeat on {0}",this.connectionName);
      }
      this.pulseRead = false;
      this.outbound.send(this.connectionName,"clientCheckPulseEvent",this.clientId);
   }
}

import flash.events.EventDispatcher;
import flash.events.NetStatusEvent;
import flash.net.SharedObject;
import flash.net.SharedObjectFlushStatus;
import mx.collections.errors.ItemPendingError;
import mx.data.IDatabaseCollection;
import mx.data.IDatabaseCursor;
import mx.data.events.DatabaseResultEvent;
import mx.data.events.DatabaseStatusEvent;
import mx.data.events.DatabaseUpdateEvent;
import mx.rpc.AsyncDispatcher;
import mx.utils.ArrayUtil;
import mx.utils.HashUtil;
import mx.utils.ObjectUtil;

class LSODBStoreCollection extends EventDispatcher implements IDatabaseCollection
{
    
   
   private var _rollBackDataCopy:Object;
   
   private var dbStore:LSODBStore;
   
   private var getRequests:Array;
   
   private var _data:Object;
   
   private var items:Array;
   
   private var _name:String;
   
   private var originalData:SharedObject;
   
   function LSODBStoreCollection(store:LSODBStore, name:String, path:String, proxy:Boolean)
   {
      super();
      this.dbStore = store;
      this._name = name;
      if(proxy)
      {
         this._data = null;
      }
      else
      {
         this.originalData = SharedObject.getLocal(HashUtil.apHash(store.name + name).toString(),path);
         this.originalData.addEventListener(NetStatusEvent.NET_STATUS,dispatchEvent);
         this._data = this.originalData.data.values;
         if(this._data == null)
         {
            this._data = this.originalData.data.values = {};
            this._rollBackDataCopy = {};
         }
         else
         {
            this._rollBackDataCopy = ObjectUtil.copy(this._data);
         }
      }
   }
   
   public function get name() : String
   {
      return this._name;
   }
   
   public function createCursor() : IDatabaseCursor
   {
      this.initItems();
      return new LSODBStoreCollectionCursor(this,this.items);
   }
   
   public function count() : void
   {
      this.initItems();
      new AsyncDispatcher(dispatchEvent,[new DatabaseResultEvent(null,false,false,this.items.length)],1);
   }
   
   public function drop() : void
   {
      if(this.originalData)
      {
         this.originalData.clear();
      }
      this._data = {};
      this.items = [];
      new AsyncDispatcher(dispatchEvent,[new DatabaseStatusEvent(null,false,false,"Client.Drop.Success",DatabaseStatusEvent.STATUS)],1);
   }
   
   public function get(key:Object) : Object
   {
      var ipe:ItemPendingError = null;
      this.checkConnected();
      if(this._data == null)
      {
         if(this.getRequests == null)
         {
            this.getRequests = [];
         }
         ipe = new ItemPendingError("A request for the item is now pending.");
         this.getRequests.push({
            "token":ipe,
            "key":key
         });
         throw ipe;
      }
      return ObjectUtil.copy(this._data[key]);
   }
   
   public function put(key:Object, value:Object) : void
   {
      var oldValue:Object = null;
      var kind:String = null;
      this.checkConnected();
      try
      {
         this.dbStore.acquireLock();
         if(this._data == null)
         {
            this._data = {};
         }
         oldValue = this._data[key];
         kind = oldValue == null?DatabaseUpdateEvent.INSERT:DatabaseUpdateEvent.UPDATE;
         var value:Object = ObjectUtil.copy(value);
         this._data[key] = value;
         this.initItems();
         this.dbStore.internalPut(key,value,kind,this);
      }
      finally
      {
         this.dbStore.releaseLock();
      }
   }
   
   public function remove(key:Object) : void
   {
      var indx:int = 0;
      this.checkConnected();
      try
      {
         this.dbStore.acquireLock();
         if(this._data != null)
         {
            delete this._data[key];
         }
         if(this.items != null && this.items.length > 0)
         {
            indx = ArrayUtil.getItemIndex(key,this.items);
            if(indx != -1)
            {
               this.items.splice(indx,1);
            }
         }
         this.dbStore.internalRemove(key,this);
      }
      finally
      {
         this.dbStore.releaseLock();
      }
   }
   
   public function removeAll() : void
   {
      this.checkConnected();
      try
      {
         this.dbStore.acquireLock();
         this._data = {};
         this.items = [];
         this.dbStore.internalRemoveAll(this);
      }
      finally
      {
         this.dbStore.releaseLock();
      }
   }
   
   function get data() : Object
   {
      return this._data;
   }
   
   function set data(value:Object) : void
   {
      var i:* = null;
      var responders:Array = null;
      var pendingRequest:Object = null;
      var j:uint = 0;
      var k:uint = 0;
      if(this._data == null)
      {
         this._data = value;
      }
      else
      {
         for(i in value)
         {
            this._data[i] = value[i];
         }
      }
      if(this.getRequests != null)
      {
         for(j = 0; j < this.getRequests.length; j++)
         {
            pendingRequest = this.getRequests[j];
            responders = pendingRequest.token.responders;
            for(k = 0; k < responders.length; k++)
            {
               responders[k].result(this._data[pendingRequest.key]);
            }
         }
         this.getRequests = null;
      }
      dispatchEvent(new DatabaseUpdateEvent(null,false,false,this.name,null,DatabaseUpdateEvent.UPDATE));
   }
   
   function getOriginalData() : Object
   {
      return this.originalData.data.values;
   }
   
   function flush() : String
   {
      if(this.originalData)
      {
         return this.originalData.flush();
      }
      return SharedObjectFlushStatus.FLUSHED;
   }
   
   function release() : void
   {
      this.dbStore = null;
   }
   
   function commit() : void
   {
      this.originalData.data.values = this._data;
      this._rollBackDataCopy = ObjectUtil.copy(this._data);
   }
   
   function restore(data:Object) : void
   {
   }
   
   function rollback() : void
   {
      this._data = this._rollBackDataCopy;
      this.originalData.data.values = this._data;
   }
   
   private function checkConnected() : void
   {
      if(this.dbStore == null)
      {
         throw new Error("Operation can not be performed. Collection is invalid.");
      }
   }
   
   private function initItems() : void
   {
      var i:* = null;
      this.items = [];
      for(i in this._data)
      {
         this.items.push(i);
      }
   }
}

import mx.data.IDatabaseCursor;

class LSODBStoreCollectionCursor implements IDatabaseCursor
{
    
   
   private var collection:LSODBStoreCollection;
   
   private var items:Array;
   
   private var index:int = 0;
   
   function LSODBStoreCollectionCursor(collection:LSODBStoreCollection, items:Array)
   {
      super();
      this.items = items;
      this.collection = collection;
   }
   
   public function get afterLast() : Boolean
   {
      return this.index >= this.items.length;
   }
   
   public function get beforeFirst() : Boolean
   {
      return this.index < 0;
   }
   
   public function get current() : Object
   {
      if(this.index < 0 || this.index == this.items.length)
      {
         throw new Error("Invalid cursor.");
      }
      return this.collection.get(this.items[this.index]);
   }
   
   public function moveNext() : void
   {
      this.index++;
   }
   
   public function movePrevious() : void
   {
      this.index--;
   }
   
   public function seek(offset:int, location:int = -1, prefetch:int = 0) : void
   {
      if(location == -1)
      {
         this.index = 0;
      }
      else if(location == 1)
      {
         this.index = this.items.length - 1;
      }
      this.index = this.index + offset;
   }
}

class JournalEntry
{
    
   
   public var collection:String;
   
   public var data:Object;
   
   public var isDelete:Boolean;
   
   public var key:Object;
   
   function JournalEntry()
   {
      super();
   }
}
