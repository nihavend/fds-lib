package mx.data.messages
{
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import mx.messaging.messages.IMessage;
   
   [RemoteClass(alias="flex.data.messages.PagedMessage")]
   public class PagedMessage extends SequencedMessage
   {
      
      private static const PAGE_COUNT_FLAG:uint = 1;
      
      private static const PAGE_INDEX_FLAG:uint = 2;
       
      
      public var pageCount:int;
      
      public var pageIndex:int;
      
      public function PagedMessage()
      {
         super();
      }
      
      override public function getSmallMessage() : IMessage
      {
         if((this as Object).constructor == PagedMessage)
         {
            return new PagedMessageExt(this);
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
               if((flags & PAGE_COUNT_FLAG) != 0)
               {
                  this.pageCount = input.readObject() as int;
               }
               if((flags & PAGE_INDEX_FLAG) != 0)
               {
                  this.pageIndex = input.readObject() as int;
               }
               reservedPosition = 2;
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
         if(this.pageCount != 0)
         {
            flags = flags | PAGE_COUNT_FLAG;
         }
         if(this.pageIndex != 0)
         {
            flags = flags | PAGE_INDEX_FLAG;
         }
         output.writeByte(flags);
         if(this.pageCount != 0)
         {
            output.writeObject(this.pageCount);
         }
         if(this.pageIndex != 0)
         {
            output.writeObject(this.pageIndex);
         }
      }
   }
}
