package mx.data.messages
{
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import mx.data.UpdateCollectionRange;
   import mx.messaging.messages.IMessage;
   import mx.utils.ObjectUtil;
   
   [RemoteClass(alias="flex.data.messages.UpdateCollectionMessage")]
   public class UpdateCollectionMessage extends DataMessage
   {
      
      public static const CLIENT_UPDATE:int = 0;
      
      public static const SERVER_UPDATE:int = 1;
      
      public static const SERVER_OVERRIDE:int = 2;
      
      private static const COLLECTION_ID_FLAG:uint = 1;
      
      private static const REPLACE_FLAG:uint = 2;
      
      private static const UPDATE_MODE_FLAG:uint = 4;
       
      
      public var collectionId:Object;
      
      public var replace:Boolean;
      
      public var updateMode:int;
      
      public function UpdateCollectionMessage()
      {
         super();
         operation = DataMessage.UPDATE_COLLECTION_OPERATION;
         this.updateMode = CLIENT_UPDATE;
      }
      
      public function addItemIdentityChange(updateType:int, position:int, identity:Object) : Boolean
      {
         var range:UpdateCollectionRange = null;
         var newPos:int = 0;
         var rangeArray:Array = body as Array;
         if(this.cancelItemIdentityChange(updateType,position,identity))
         {
            return false;
         }
         if(rangeArray == null)
         {
            range = new UpdateCollectionRange();
            range.position = position;
            range.updateType = updateType;
            range.identities = [identity];
            body = [];
            body.push(range);
         }
         else
         {
            range = rangeArray[rangeArray.length - 1];
            if(updateType == UpdateCollectionRange.INSERT_INTO_COLLECTION)
            {
               newPos = range.position + range.identities.length;
            }
            else
            {
               newPos = range.position;
            }
            if(position != newPos || range.updateType != updateType)
            {
               range = new UpdateCollectionRange();
               range.position = position;
               range.updateType = updateType;
               range.identities = [identity];
               rangeArray.push(range);
            }
            else
            {
               range.identities.push(identity);
            }
         }
         return true;
      }
      
      public function appendUpdateCollectionMessage(toAppend:UpdateCollectionMessage) : void
      {
         var rangeArray:Array = body as Array;
         rangeArray.concat(toAppend.body as Array);
      }
      
      public function containsIdentity(identity:Object) : Boolean
      {
         var range:UpdateCollectionRange = null;
         var identities:Array = null;
         var j:int = 0;
         var rangeArray:Array = body as Array;
         for(var i:int = 0; i < rangeArray.length; i++)
         {
            range = UpdateCollectionRange(rangeArray[i]);
            identities = range.identities;
            for(j = 0; j < identities.length; j++)
            {
               if(ObjectUtil.compare(identity,identities[j]) == 0)
               {
                  return true;
               }
            }
         }
         return false;
      }
      
      public function replaceIdentity(fromIdentity:Object, toIdentity:Object) : void
      {
         var range:UpdateCollectionRange = null;
         var identities:Array = null;
         var j:int = 0;
         var rangeArray:Array = body as Array;
         for(var i:int = 0; i < rangeArray.length; i++)
         {
            range = UpdateCollectionRange(rangeArray[i]);
            identities = range.identities;
            for(j = 0; j < identities.length; j++)
            {
               if(ObjectUtil.compare(fromIdentity,identities[j]) == 0)
               {
                  identities[j] = toIdentity;
               }
            }
         }
      }
      
      public function isSameUpdate(other:UpdateCollectionMessage) : Boolean
      {
         var range:UpdateCollectionRange = null;
         var otherRange:UpdateCollectionRange = null;
         var j:int = 0;
         var rangeArray:Array = body as Array;
         var otherRangeArray:Array = other.body as Array;
         if(otherRangeArray.length != rangeArray.length)
         {
            return false;
         }
         for(var i:int = 0; i < rangeArray.length; i++)
         {
            range = UpdateCollectionRange(rangeArray[i]);
            otherRange = UpdateCollectionRange(otherRangeArray[i]);
            if(range.updateType != otherRange.updateType)
            {
               return false;
            }
            if(range.identities.length != otherRange.identities.length)
            {
               return false;
            }
            if(range.position != otherRange.position)
            {
               return false;
            }
            for(j = 0; j < range.identities.length; j++)
            {
               if(ObjectUtil.compare(range.identities[j],otherRange.identities[j]) != 0)
               {
                  return false;
               }
            }
         }
         return true;
      }
      
      override public function getSmallMessage() : IMessage
      {
         if((this as Object).constructor == UpdateCollectionMessage)
         {
            return new UpdateCollectionMessageExt(this);
         }
         return null;
      }
      
      override public function readExternal(input:IDataInput) : void
      {
         var flags:uint = 0;
         var reservedPosition:uint = 0;
         var j:uint = 0;
         super.readExternal(input);
         var flagsArray:Array = readFlags(input);
         for(var i:uint = 0; i < flagsArray.length; i++)
         {
            flags = flagsArray[i] as uint;
            reservedPosition = 0;
            if(i == 0)
            {
               if((flags & COLLECTION_ID_FLAG) != 0)
               {
                  this.collectionId = input.readObject();
               }
               if((flags & REPLACE_FLAG) != 0)
               {
                  this.replace = input.readObject() as Boolean;
               }
               if((flags & UPDATE_MODE_FLAG) != 0)
               {
                  this.updateMode = input.readObject();
               }
               reservedPosition = 3;
            }
            if(flags >> reservedPosition != 0)
            {
               for(j = reservedPosition; j < 6; j++)
               {
                  if((flags >> j & 1) != 0)
                  {
                     input.readObject();
                  }
               }
            }
         }
      }
      
      override public function writeExternal(output:IDataOutput) : void
      {
         super.writeExternal(output);
         var flags:uint = 0;
         if(this.collectionId != null)
         {
            flags = flags | COLLECTION_ID_FLAG;
         }
         flags = flags | REPLACE_FLAG;
         if(this.updateMode != 0)
         {
            flags = flags | UPDATE_MODE_FLAG;
         }
         output.writeByte(flags);
         if(this.collectionId != null)
         {
            output.writeObject(this.collectionId);
         }
         output.writeObject(this.replace);
         if(this.updateMode != 0)
         {
            output.writeObject(this.updateMode);
         }
      }
      
      function getRangeInfoForIdentity(identity:Object) : Array
      {
         var range:UpdateCollectionRange = null;
         var identities:Array = null;
         var i:int = 0;
         var j:int = 0;
         var rangeArray:Array = body as Array;
         var result:Array = [];
         if(rangeArray != null)
         {
            for(i = 0; i < rangeArray.length; i++)
            {
               range = UpdateCollectionRange(rangeArray[i]);
               identities = range.identities;
               for(j = 0; j < identities.length; j++)
               {
                  if(ObjectUtil.compare(identity,identities[j]) == 0)
                  {
                     result.push({
                        "rangeIndex":i,
                        "idIndex":j
                     });
                  }
               }
            }
         }
         return result;
      }
      
      function removeRanges(rangeInfos:Array, adds:Boolean = true, removes:Boolean = true) : void
      {
         var info:Object = null;
         for(var i:int = 0; i < rangeInfos.length; i++)
         {
            info = rangeInfos[i];
            this.removeUpdate(info.rangeIndex,info.idIndex,adds,removes);
         }
      }
      
      private function cancelItemIdentityChange(updateType:int, position:int, identity:Object) : Boolean
      {
         var range:UpdateCollectionRange = null;
         var j:int = 0;
         var rangeArray:Array = body as Array;
         if(rangeArray == null)
         {
            return false;
         }
         var i:int = rangeArray.length - 1;
         while(true)
         {
            if(i < 0)
            {
               return false;
            }
            range = UpdateCollectionRange(rangeArray[i]);
            for(j = 0; j < range.identities.length; j++)
            {
               if(ObjectUtil.compare(range.identities[j],identity) == 0)
               {
                  break;
               }
            }
            if(j != range.identities.length)
            {
               break;
            }
            i--;
         }
         if(updateType != range.updateType && (updateType == UpdateCollectionRange.DELETE_FROM_COLLECTION || position == range.position + j))
         {
            this.removeUpdate(i,j,true,true);
            return true;
         }
         return false;
      }
      
      private function removeUpdate(rangeIndex:int, idIndex:int, adds:Boolean, removes:Boolean) : void
      {
         var newRange:UpdateCollectionRange = null;
         var rangeArray:Array = body as Array;
         var range:UpdateCollectionRange = rangeArray[rangeIndex];
         var updateType:int = range.updateType;
         var idsLength:int = range.identities.length;
         if(!adds && updateType == UpdateCollectionRange.INSERT_INTO_COLLECTION)
         {
            return;
         }
         if(!removes && updateType == UpdateCollectionRange.DELETE_FROM_COLLECTION)
         {
            return;
         }
         range.identities.splice(idIndex,1);
         if(range.identities.length == 0)
         {
            rangeArray.splice(rangeIndex,1);
            rangeIndex--;
            if(rangeArray.length == 0)
            {
               body = null;
               return;
            }
         }
         var operDel:int = 1;
         var operIns:int = -1;
         if(updateType == UpdateCollectionRange.DELETE_FROM_COLLECTION)
         {
            if(idIndex == 0)
            {
               range.position++;
            }
            else if(idIndex < idsLength - 1)
            {
               newRange = new UpdateCollectionRange();
               newRange.identities = range.identities.slice(idIndex,range.identities.length);
               newRange.position = range.position + idIndex;
               range.identities.splice(idIndex);
               rangeArray.splice(++rangeIndex,0,newRange);
            }
            operDel = 1;
            operIns = 1;
         }
         for(var i:int = rangeIndex + 1; i < rangeArray.length; i++)
         {
            range = rangeArray[i];
            if(updateType == UpdateCollectionRange.INSERT_INTO_COLLECTION)
            {
               range.position = range.position + operIns;
            }
            else
            {
               range.position = range.position + operDel;
            }
         }
      }
   }
}
