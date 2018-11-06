package mx.data.mxml
{
   import mx.core.IMXMLObject;
   
   public class ManagedRemoteServiceOperation extends mx.data.ManagedRemoteServiceOperation implements IMXMLObject
   {
       
      
      var document:Object;
      
      var id:String;
      
      public function ManagedRemoteServiceOperation(remoteObject:mx.data.ManagedRemoteService = null, name:String = null)
      {
         super(remoteObject,name);
      }
      
      public function initialized(document:Object, id:String) : void
      {
         this.document = document;
         this.id = id;
      }
   }
}
