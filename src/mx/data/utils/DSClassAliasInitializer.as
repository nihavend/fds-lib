package mx.data.utils
{
   import flash.net.registerClassAlias;
   import mx.data.CacheDataDescriptor;
   import mx.data.ChangedItems;
   import mx.data.Conflict;
   import mx.data.DataMessageCache;
   import mx.data.DynamicProperty;
   import mx.data.ManagedAssociation;
   import mx.data.ManagedObjectProxy;
   import mx.data.MessageBatch;
   import mx.data.Metadata;
   import mx.data.UpdateCollectionRange;
   import mx.data.messages.DataErrorMessage;
   import mx.data.messages.DataMessage;
   import mx.data.messages.DataMessageExt;
   import mx.data.messages.ManagedRemoteServiceMessage;
   import mx.data.messages.PagedMessage;
   import mx.data.messages.PagedMessageExt;
   import mx.data.messages.SequencedMessage;
   import mx.data.messages.SequencedMessageExt;
   import mx.data.messages.SyncFillRequest;
   import mx.data.messages.UpdateCollectionMessage;
   import mx.data.messages.UpdateCollectionMessageExt;
   import mx.utils.RpcClassAliasInitializer;
   
   public class DSClassAliasInitializer
   {
       
      
      public function DSClassAliasInitializer()
      {
         super();
      }
      
      public static function registerClassAliases() : void
      {
         RpcClassAliasInitializer.registerClassAliases();
         registerClassAlias("flex.data.ChangedItems",ChangedItems);
         registerClassAlias("flex.data.Conflict",CacheDataDescriptor);
         registerClassAlias("flex.data.messages.DataErrorMessage",DataErrorMessage);
         registerClassAlias("flex.data.messages.DataMessage",DataMessage);
         registerClassAlias("DSD",DataMessageExt);
         registerClassAlias("flex.messaging.io.ManagedObjectProxy",ManagedObjectProxy);
         registerClassAlias("flex.data.messages.PagedMessage",PagedMessage);
         registerClassAlias("DSP",PagedMessageExt);
         registerClassAlias("flex.data.messages.ManagedRemoteServiceMessage",ManagedRemoteServiceMessage);
         registerClassAlias("flex.data.messages.SequencedMessage",SequencedMessage);
         registerClassAlias("DSQ",SequencedMessageExt);
         registerClassAlias("flex.messaging.io.SerializationProxy",SerializationProxy);
         registerClassAlias("flex.data.messages.SyncFillRequest",SyncFillRequest);
         registerClassAlias("flex.data.messages.UpdateCollectionMessage",UpdateCollectionMessage);
         registerClassAlias("DSU",UpdateCollectionMessageExt);
         registerClassAlias("flex.data.UpdateCollectionRange",UpdateCollectionRange);
         registerClassAlias("mx.data.CacheDataDescriptor",CacheDataDescriptor);
         registerClassAlias("mx.data.Conflict",Conflict);
         registerClassAlias("mx.data.DataMessageCache",DataMessageCache);
         registerClassAlias("mx.data.DynamicProperty",DynamicProperty);
         registerClassAlias("mx.data.ManagedAssociation",ManagedAssociation);
         registerClassAlias("mx.data.MessageBatch",MessageBatch);
         registerClassAlias("mx.data.Metadata",Metadata);
      }
   }
}
