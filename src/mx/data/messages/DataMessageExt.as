package mx.data.messages
{
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   
   [RemoteClass(alias="DSD")]
   public class DataMessageExt extends DataMessage implements IExternalizable
   {
       
      
      private var _message:DataMessage;
      
      public function DataMessageExt(message:DataMessage = null)
      {
         super();
         this._message = message;
      }
      
      override public function writeExternal(output:IDataOutput) : void
      {
         if(this._message != null)
         {
            this._message.writeExternal(output);
         }
         else
         {
            super.writeExternal(output);
         }
      }
      
      override public function get messageId() : String
      {
         if(this._message != null)
         {
            return this._message.messageId;
         }
         return super.messageId;
      }
   }
}
