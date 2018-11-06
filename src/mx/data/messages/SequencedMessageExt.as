package mx.data.messages
{
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   
   [RemoteClass(alias="DSQ")]
   public class SequencedMessageExt extends SequencedMessage implements IExternalizable
   {
       
      
      private var _message:SequencedMessage;
      
      public function SequencedMessageExt(message:SequencedMessage = null)
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
   }
}
