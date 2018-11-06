package mx.data
{
   import mx.collections.ArrayList;
   import mx.data.messages.DataErrorMessage;
   import mx.data.messages.DataMessage;
   import mx.events.CollectionEvent;
   import mx.events.CollectionEventKind;
   import mx.events.PropertyChangeEvent;
   
   public class Conflicts extends ArrayList
   {
       
      
      private var _dataService:ConcreteDataService;
      
      public function Conflicts(dataService:ConcreteDataService = null)
      {
         super();
         this.dataService = dataService;
      }
      
      private function propagateCollectionEvent(event:CollectionEvent) : void
      {
         var i:int = 0;
         var c:Conflict = null;
         var item:* = undefined;
         var collectionEvent:CollectionEvent = null;
         switch(event.kind)
         {
            case CollectionEventKind.ADD:
            case CollectionEventKind.REMOVE:
            case CollectionEventKind.REPLACE:
               for(i = 0; i < event.items.length; i++)
               {
                  item = event.items[i];
                  if(item is PropertyChangeEvent)
                  {
                     c = Conflict(PropertyChangeEvent(item).oldValue);
                  }
                  else
                  {
                     c = Conflict(item);
                  }
                  if(c.concreteDataService == this._dataService)
                  {
                     collectionEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
                     collectionEvent.kind = event.kind;
                     if(event.kind == CollectionEventKind.ADD)
                     {
                        collectionEvent.location = getItemIndex(c);
                     }
                     else
                     {
                        collectionEvent.location = event.location;
                     }
                     if(collectionEvent.location != -1)
                     {
                        collectionEvent.items = [item];
                        dispatchEvent(collectionEvent);
                     }
                  }
               }
               break;
            case CollectionEventKind.RESET:
               dispatchEvent(event);
         }
      }
      
      [Bindable(event="propertyChange")]
      public function get resolved() : Boolean
      {
         var items:Array = this.source;
         for(var i:int = 0; i < items.length; i++)
         {
            if(!Conflict(items[i]).resolved)
            {
               return false;
            }
         }
         return true;
      }
      
      public function acceptAllClient() : void
      {
         var c:Conflict = null;
         var items:Array = this.source;
         for(var i:int = 0; i < items.length; i++)
         {
            c = Conflict(items[i]);
            c.acceptClient();
         }
         removeAll();
      }
      
      public function acceptAllServer() : void
      {
         var c:Conflict = null;
         var items:Array = this.source;
         for(var i:int = 0; i < items.length; i++)
         {
            c = Conflict(items[i]);
            c.acceptServer();
         }
         removeAll();
      }
      
      public function removeAllResolved() : void
      {
         var c:Conflict = null;
         var items:Array = this.source;
         for(var i:int = items.length - 1; i >= 0; i--)
         {
            c = Conflict(items[i]);
            if(c.resolved)
            {
               removeItemAt(i);
            }
         }
      }
      
      public function getConflict(item:Object) : Conflict
      {
         var c:Conflict = null;
         var items:Array = this.source;
         for(var i:int = 0; i < items.length; i++)
         {
            c = Conflict(items[i]);
            if(c.clientObject == item)
            {
               return c;
            }
         }
         return null;
      }
      
      public function addConflict(newConflict:Conflict) : Boolean
      {
         var i:int = 0;
         var resolvedBefore:Boolean = false;
         var dsConflicts:Conflicts = null;
         var dsResolvedBefore:Boolean = false;
         var oldConflict:Conflict = null;
         if(this._dataService != null)
         {
            return this._dataService.dataStore.conflicts.addConflict(newConflict);
         }
         var existingConflicts:Array = this.source;
         if(newConflict.cause)
         {
            for(i = 0; i < existingConflicts.length; i++)
            {
               oldConflict = existingConflicts[i];
               if(oldConflict.matches(newConflict))
               {
                  setItemAt(newConflict,i);
                  return true;
               }
            }
            resolvedBefore = this.resolved;
            dsConflicts = newConflict.concreteDataService.conflicts;
            dsResolvedBefore = dsConflicts.resolved;
            addItem(newConflict);
            if(resolvedBefore)
            {
               this.resolvedChanged(true,false);
            }
            if(dsResolvedBefore)
            {
               dsConflicts.resolvedChanged(true,false);
            }
            return true;
         }
         return false;
      }
      
      function resolvedChanged(oldValue:Boolean, newValue:Boolean) : void
      {
         dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"resolved",oldValue,newValue));
      }
      
      public function raiseConflict(dataManager:DataManager, cause:DataMessage, serverObject:Object, conflictingProperties:Array) : void
      {
         var errMsg:DataErrorMessage = new DataErrorMessage();
         errMsg.cause = cause;
         errMsg.propertyNames = conflictingProperties;
         errMsg.serverObject = serverObject;
         dataManager.dataStore.processConflict(dataManager.concreteDataService,errMsg,cause);
      }
      
      [Bindable("collectionChange")]
      override public function get length() : int
      {
         return this.source.length;
      }
      
      override public function get source() : Array
      {
         var allConflicts:Conflicts = null;
         var toReturn:Array = null;
         var i:int = 0;
         var conflict:Conflict = null;
         if(this._dataService == null)
         {
            return super.source;
         }
         allConflicts = this._dataService.dataStore.conflicts;
         if(allConflicts.length == 0)
         {
            return allConflicts.source;
         }
         toReturn = new Array();
         for(i = 0; i < allConflicts.length; i++)
         {
            conflict = Conflict(allConflicts.getItemAt(i));
            if(this._dataService.isSubtypeOf(conflict.concreteDataService))
            {
               toReturn.push(conflict);
            }
         }
         return toReturn;
      }
      
      function set dataService(cds:ConcreteDataService) : void
      {
         this._dataService = cds;
         if(this._dataService != null)
         {
            this.dataService.dataStore.conflicts.addEventListener(CollectionEvent.COLLECTION_CHANGE,this.propagateCollectionEvent);
         }
      }
      
      function get dataService() : ConcreteDataService
      {
         return this._dataService;
      }
      
      override public function toString() : String
      {
         var s:String = null;
         var i:int = 0;
         if(this.length == 0)
         {
            return "no conflicts";
         }
         s = this.length + " conflicts [";
         for(i = 0; i < this.length; i++)
         {
            s = s + Conflict(getItemAt(i)).toString();
         }
         s = s + "]";
         return s;
      }
   }
}
