package mx.data
{
   import mx.core.mx_internal;
   import mx.data.utils.Managed;
   import mx.utils.ObjectUtil;
   
   public class ConflictDetector
   {
       
      
      private var _dataService:ConcreteDataService;
      
      public function ConflictDetector(dataService:ConcreteDataService)
      {
         super();
         this._dataService = dataService;
      }
      
      public function checkCreate(remoteChange:IChangeObject, localChange:IChangeObject) : void
      {
         if(localChange != null && ObjectUtil.compare(remoteChange.identity,localChange.identity) == 0)
         {
            remoteChange.conflict("Local created item is in conflict with remotely created item",localChange.changedPropertyNames);
         }
      }
      
      public function checkDelete(remoteChange:IChangeObject, localChange:IChangeObject) : void
      {
         if(localChange != null)
         {
            if(localChange.isUpdate() && remoteChange.previousVersion != null)
            {
               remoteChange.conflict("Local item was updated and is in conflict with pushed delete.",localChange.changedPropertyNames);
            }
         }
      }
      
      public function checkRemoveFromFill(localChange:IChangeObject, fillParameters:Object) : void
      {
         if(localChange != null)
         {
            if(localChange.isUpdate())
            {
               localChange.conflict("Local item was updated but has changed on the server such that it no longer" + "belongs to the fill with parameters: " + fillParameters,localChange.changedPropertyNames);
            }
         }
      }
      
      public function checkUpdate(remoteChange:IChangeObject, localChange:IChangeObject) : void
      {
         var localVersion:Object = null;
         var remoteVersion:Object = null;
         var remoteIds:Object = null;
         var remoteChanges:Array = null;
         var i:int = 0;
         var comparison:int = 0;
         var prop:Object = null;
         var association:ManagedAssociation = null;
         var conflictingProps:Array = null;
         if(localChange != null)
         {
            localVersion = localChange.currentVersion;
            if(localChange.isUpdate())
            {
               remoteVersion = remoteChange.newVersion;
               remoteIds = remoteChange.message.headers.newReferencedIds;
               if(!remoteVersion)
               {
                  return;
               }
               remoteChanges = remoteChange.changedPropertyNames;
               for(i = 0; i < remoteChanges.length; i++)
               {
                  prop = remoteChanges[i];
                  if(localChange.changedPropertyNames.indexOf(prop) != -1)
                  {
                     association = this._dataService.metadata.associations[prop];
                     if(association != null && association.lazy)
                     {
                        comparison = ObjectUtil.compare(remoteIds[prop],Managed.getReferencedIds(localVersion)[prop]);
                     }
                     else
                     {
                        comparison = Managed.mx_internal::compare(remoteVersion[prop],localVersion[prop],-1,["uid"]);
                     }
                     if(comparison != 0)
                     {
                        if(conflictingProps == null)
                        {
                           conflictingProps = [];
                        }
                        conflictingProps.push(prop);
                     }
                  }
               }
               if(conflictingProps != null)
               {
                  remoteChange.conflict("Local item has changes to properties that conflict with remote change.",conflictingProps);
               }
            }
            else if(localChange.isDelete())
            {
               remoteChange.conflict("Local item has been deleted.",remoteChange.changedPropertyNames);
            }
         }
      }
   }
}
