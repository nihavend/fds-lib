package mx.data.utils
{
   import flash.net.getClassByAlias;
   import flash.utils.ByteArray;
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   import flash.xml.XMLDocument;
   import flash.xml.XMLNode;
   import mx.collections.ArrayCollection;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.utils.ObjectProxy;
   import mx.utils.ObjectUtil;
   
   [RemoteClass(alias="flex.messaging.io.SerializationProxy")]
   [ResourceBundle("data")]
   public class SerializationProxy implements IExternalizable
   {
      
      private static const UNDEFINED_TYPE:uint = 0;
      
      private static const NULL_TYPE:uint = 1;
      
      private static const FALSE_TYPE:uint = 2;
      
      private static const TRUE_TYPE:uint = 3;
      
      private static const INTEGER_TYPE:uint = 4;
      
      private static const DOUBLE_TYPE:uint = 5;
      
      private static const STRING_TYPE:uint = 6;
      
      private static const XML_TYPE:uint = 7;
      
      private static const DATE_TYPE:uint = 8;
      
      private static const ARRAY_TYPE:uint = 9;
      
      private static const OBJECT_TYPE:uint = 10;
      
      private static const AVM_PLUS_XML_TYPE:uint = 11;
      
      private static const BYTE_ARRAY_TYPE:uint = 12;
      
      private static const CLASS_INFO_OPTIONS:Object = {
         "includeReadOnly":false,
         "unwrapProxy":false,
         "includeTransient":false
      };
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      private var instanceTable:Array;
      
      private var traitsTable:Array;
      
      private var stringTable:Array;
      
      private var descriptor:SerializationDescriptor;
      
      private var _instance:Object;
      
      public function SerializationProxy(instance:Object = null, descriptor:SerializationDescriptor = null)
      {
         super();
         this._instance = instance;
         this.descriptor = descriptor;
      }
      
      public function get instance() : Object
      {
         return this._instance;
      }
      
      public function readExternal(input:IDataInput) : void
      {
         this.instanceTable = [];
         this.traitsTable = [];
         this.stringTable = [];
         try
         {
            this._instance = this.readObject(input);
         }
         finally
         {
            this.instanceTable = null;
            this.traitsTable = null;
            this.stringTable = null;
         }
      }
      
      public function writeExternal(out:IDataOutput) : void
      {
         this.instanceTable = [];
         this.traitsTable = [];
         this.stringTable = [];
         try
         {
            this.writeObject(this._instance,out,this.descriptor);
         }
         finally
         {
            this.instanceTable = null;
            this.traitsTable = null;
            this.stringTable = null;
         }
      }
      
      function readObject(input:IDataInput) : Object
      {
         var type:int = input.readByte();
         var value:Object = this.readObjectValue(input,type);
         return value;
      }
      
      private function readObjectValue(input:IDataInput, type:int) : Object
      {
         var value:Object = null;
         switch(type)
         {
            case STRING_TYPE:
               value = this.readStringWithoutType(input);
               break;
            case OBJECT_TYPE:
               value = this.readScriptObject(input);
               break;
            case ARRAY_TYPE:
               value = this.readArray(input);
               break;
            case FALSE_TYPE:
               value = false;
               break;
            case TRUE_TYPE:
               value = true;
               break;
            case INTEGER_TYPE:
               value = this.readInt(input);
               break;
            case DOUBLE_TYPE:
               value = input.readDouble();
               break;
            case UNDEFINED_TYPE:
               break;
            case NULL_TYPE:
               break;
            case DATE_TYPE:
               value = this.readDate(input);
               break;
            case XML_TYPE:
            case AVM_PLUS_XML_TYPE:
               value = this.readXMLWithoutType(input);
               break;
            case BYTE_ARRAY_TYPE:
               value = this.readByteArrayWithoutType(input);
               break;
            default:
               throw new Error(resourceManager.getString("data","invalidTypeInStream",[type]));
         }
         return value;
      }
      
      private function readArray(input:IDataInput) : Object
      {
         var array:Array = null;
         var len:int = 0;
         var i:int = 0;
         var name:String = null;
         var value:Object = null;
         var item:Object = null;
         var ref:int = this.readUInt29(input);
         if((ref & 1) == 0)
         {
            return this.getObjectReference(ref >> 1);
         }
         len = ref >> 1;
         array = [];
         for(this.instanceTable.push(array); true; )
         {
            name = this.readStringWithoutType(input);
            if(name == null || name.length == 0)
            {
               break;
            }
            if(array == null)
            {
            }
            value = this.readObject(input);
            array[name] = value;
         }
         for(i = 0; i < len; i++)
         {
            item = this.readObject(input);
            array[i] = item;
         }
         return array;
      }
      
      private function readScriptObject(input:IDataInput) : Object
      {
         var ti:TraitsInfo = null;
         var className:String = null;
         var externalizable:Boolean = false;
         var newObject:Object = null;
         var theClass:Class = null;
         var len:int = 0;
         var i:int = 0;
         var propName:String = null;
         var value:Object = null;
         var name:String = null;
         var ref:int = this.readUInt29(input);
         if((ref & 1) == 0)
         {
            return this.getObjectReference(ref >> 1);
         }
         ti = this.readTraits(ref,input);
         className = ti.className;
         externalizable = ti.externalizable;
         newObject = null;
         if(className != null && className.length > 0)
         {
            try
            {
               theClass = getClassByAlias(className);
               newObject = new theClass();
            }
            catch(te:TypeError)
            {
               newObject = new Object();
            }
         }
         else
         {
            newObject = new Object();
         }
         this.instanceTable.push(newObject);
         if(externalizable)
         {
            this.readExternalizable(className,newObject,input);
         }
         else
         {
            len = ti.properties.length;
            for(i = 0; i < len; i++)
            {
               propName = ti.properties[i];
               value = this.readObject(input);
               try
               {
                  newObject[propName] = value;
               }
               catch(e:ReferenceError)
               {
               }
            }
            if(ti.dynamic)
            {
               while(true)
               {
                  name = this.readStringWithoutType(input);
                  if(name == null || name.length == 0)
                  {
                     break;
                  }
                  value = this.readObject(input);
                  try
                  {
                     newObject[name] = value;
                  }
                  catch(e:ReferenceError)
                  {
                     continue;
                  }
               }
            }
         }
         return newObject;
      }
      
      private function readDate(input:IDataInput) : Date
      {
         var time:Number = NaN;
         var date:Date = null;
         var ref:int = this.readUInt29(input);
         if((ref & 1) == 0)
         {
            return this.getObjectReference(ref >> 1) as Date;
         }
         time = input.readDouble();
         date = new Date(time);
         this.instanceTable.push(date);
         return date;
      }
      
      private function readInt(input:IDataInput) : int
      {
         var val:int = this.readUInt29(input);
         val = val << 3 >> 3;
         return val;
      }
      
      private function readExternalizable(className:String, newObject:Object, input:IDataInput) : void
      {
         if(newObject is IExternalizable)
         {
            IExternalizable(newObject).readExternal(new ProxyDataInput(this,input));
            return;
         }
         throw new Error(resourceManager.getString("data","classNotIExternalizable",[className]));
      }
      
      private function readUInt29(input:IDataInput) : int
      {
         var value:int = 0;
         var b:int = input.readByte() & 255;
         if(b < 128)
         {
            return b;
         }
         value = (b & 127) << 7;
         b = input.readByte() & 255;
         if(b < 128)
         {
            return value | b;
         }
         value = (value | b & 127) << 7;
         b = input.readByte() & 255;
         if(b < 128)
         {
            return value | b;
         }
         value = (value | b & 127) << 8;
         b = input.readByte() & 255;
         return value | b;
      }
      
      private function readTraits(ref:int, input:IDataInput) : TraitsInfo
      {
         var externalizable:Boolean = false;
         var dynamic:Boolean = false;
         var count:int = 0;
         var className:String = null;
         var ti:TraitsInfo = null;
         var i:int = 0;
         var propName:String = null;
         if((ref & 3) == 1)
         {
            return this.getTraitsReference(ref >> 2);
         }
         externalizable = (ref & 4) == 4;
         dynamic = (ref & 8) == 8;
         count = ref >> 4;
         className = this.readStringWithoutType(input);
         ti = new TraitsInfo(className,[],dynamic,externalizable);
         for(i = 0; i < count; i++)
         {
            propName = this.readStringWithoutType(input);
            ti.properties[i] = propName;
         }
         this.traitsTable.push(ti);
         return ti;
      }
      
      private function getObjectReference(ref:int) : Object
      {
         return this.instanceTable[ref];
      }
      
      private function getTraitsReference(ref:int) : TraitsInfo
      {
         return TraitsInfo(this.traitsTable[ref]);
      }
      
      function writeObject(value:Object, out:IDataOutput, descriptor:SerializationDescriptor) : void
      {
         if(value is int || value is uint || value is Number || value is Boolean || value == null || value is XML || value is XMLDocument || value is XMLNode || value is ByteArray)
         {
            out.writeObject(value);
         }
         else if(value is String)
         {
            this.writeString(value as String,out);
         }
         else if(value is Array)
         {
            this.writeArray(value as Array,out,descriptor);
         }
         else if(value is Date)
         {
            this.writeDate(value as Date,out);
         }
         else
         {
            this.writeScriptObject(value,out,descriptor);
         }
      }
      
      function writeScriptObject(outputObject:Object, out:IDataOutput, descriptor:SerializationDescriptor) : void
      {
         var classInfo:Object = null;
         var className:String = null;
         var externalizable:Boolean = false;
         var properties:Array = null;
         var propName:String = null;
         var value:Object = null;
         var i:uint = 0;
         var includedProps:Array = null;
         var count:uint = 0;
         var dynamic:Boolean = false;
         var ti:TraitsInfo = null;
         var childDescriptor:SerializationDescriptor = null;
         out.writeByte(OBJECT_TYPE);
         if(outputObject is ObjectProxy)
         {
            outputObject = ObjectProxy(outputObject).object;
         }
         if(!this.byReference(outputObject,out))
         {
            classInfo = ObjectUtil.getClassInfo(outputObject,null,CLASS_INFO_OPTIONS);
            className = classInfo.alias;
            externalizable = outputObject is IExternalizable;
            properties = classInfo.properties;
            i = 0;
            includedProps = null;
            if(descriptor != null)
            {
               includedProps = descriptor.getIncludes();
            }
            if(includedProps == null)
            {
               includedProps = [];
            }
            for(i = 0; i < properties.length; i++)
            {
               propName = properties[i];
               if(!this.isExcluded(propName,descriptor))
               {
                  includedProps.push(propName);
               }
            }
            count = includedProps.length;
            dynamic = classInfo.dynamic == true;
            if(externalizable)
            {
               count = 0;
               includedProps = [];
            }
            ti = new TraitsInfo(className,includedProps,dynamic,externalizable);
            if(!this.traitsByReference(ti,out))
            {
               this.writeUInt29(3 | (!!externalizable?4:0) | (!!dynamic?8:0) | count << 4,out);
               this.writeStringWithoutType(className,out);
               for(i = 0; i < count; i++)
               {
                  propName = includedProps[i];
                  this.writeStringWithoutType(propName,out);
               }
            }
            childDescriptor = null;
            if(externalizable)
            {
               IExternalizable(outputObject).writeExternal(new ProxyDataOutput(this,out,outputObject is ArrayCollection?descriptor:null));
            }
            for(i = 0; i < count; i++)
            {
               propName = includedProps[i];
               value = outputObject[propName];
               if(descriptor != null)
               {
                  childDescriptor = descriptor[propName];
               }
               this.writeObject(value,out,childDescriptor);
            }
            if(dynamic)
            {
               this.writeStringWithoutType("",out);
            }
         }
      }
      
      function writeArray(array:Array, out:IDataOutput, descriptor:SerializationDescriptor) : void
      {
         var sparse:Array = null;
         var dense:Array = null;
         var j:uint = 0;
         var i:* = null;
         var k:int = 0;
         var s:* = null;
         out.writeByte(ARRAY_TYPE);
         if(!this.byReference(array,out))
         {
            sparse = null;
            dense = [];
            j = 0;
            for(i in array)
            {
               if(sparse != null)
               {
                  sparse[i] = array[i];
               }
               else if(j == uint(i))
               {
                  dense[i] = array[i];
                  j++;
               }
               else
               {
                  sparse = [];
                  sparse[i] = array[i];
               }
            }
            this.writeUInt29(dense.length << 1 | 1,out);
            if(sparse != null && sparse.length > 0)
            {
               for(s in sparse)
               {
                  this.writeStringWithoutType(s,out);
                  this.writeObject(sparse[s],out,descriptor);
               }
            }
            this.writeStringWithoutType("",out);
            for(k = 0; k < dense.length; k++)
            {
               this.writeObject(dense[k],out,descriptor);
            }
         }
      }
      
      private function writeString(str:String, out:IDataOutput) : void
      {
         out.writeByte(STRING_TYPE);
         this.writeStringWithoutType(str,out);
      }
      
      private function writeDate(date:Date, out:IDataOutput) : void
      {
         out.writeByte(DATE_TYPE);
         if(!this.byReference(date,out))
         {
            this.writeUInt29(1,out);
            out.writeDouble(date.time);
         }
      }
      
      private function byReference(instance:Object, out:IDataOutput) : Boolean
      {
         for(var i:uint = 0; i < this.instanceTable.length; i++)
         {
            if(instance === this.instanceTable[i])
            {
               this.writeUInt29(i << 1,out);
               return true;
            }
         }
         this.instanceTable.push(instance);
         return false;
      }
      
      private function stringByReference(str:String, out:IDataOutput) : Boolean
      {
         for(var i:uint = 0; i < this.stringTable.length; i++)
         {
            if(str == this.stringTable[i])
            {
               this.writeUInt29(i << 1,out);
               return true;
            }
         }
         this.stringTable.push(str);
         return false;
      }
      
      private function traitsByReference(ti:TraitsInfo, out:IDataOutput) : Boolean
      {
         for(var i:uint = 0; i < this.traitsTable.length; i++)
         {
            if(this.traitsInfoEquals(ti,this.traitsTable[i]))
            {
               this.writeUInt29(i << 2 | 1,out);
               return true;
            }
         }
         this.traitsTable.push(ti);
         return false;
      }
      
      private function traitsInfoEquals(ti1:TraitsInfo, ti2:TraitsInfo) : Boolean
      {
         if(ti1.className != ti2.className || ti1.properties.length != ti2.properties.length || ti1.dynamic != ti2.dynamic || ti1.externalizable != ti2.externalizable)
         {
            return false;
         }
         for(var i:int = 0; i < ti1.properties.length; i++)
         {
            if(ti1.properties[i] != ti2.properties[i])
            {
               return false;
            }
         }
         return true;
      }
      
      private function isExcluded(propName:String, descriptor:SerializationDescriptor) : Boolean
      {
         var excludes:Array = null;
         var i:uint = 0;
         var excludeName:String = null;
         var excluded:Boolean = false;
         if(descriptor != null && descriptor.getExcludes() != null)
         {
            excludes = descriptor.getExcludes();
            for(i = 0; i < excludes.length; i++)
            {
               excludeName = excludes[i];
               if(excludeName == propName)
               {
                  excluded = true;
                  break;
               }
            }
         }
         return excluded;
      }
      
      private function readXMLWithoutType(input:IDataInput) : XML
      {
         var xml:String = null;
         var len:int = 0;
         var ref:int = this.readUInt29(input);
         if((ref & 1) == 0)
         {
            xml = this.instanceTable[ref >> 1];
         }
         else
         {
            len = ref >> 1;
            if(len == 0)
            {
               xml = "";
            }
            else
            {
               xml = input.readUTFBytes(len);
            }
            this.instanceTable.push(xml);
         }
         return new XML(xml);
      }
      
      private function readByteArrayWithoutType(input:IDataInput) : ByteArray
      {
         var ba:ByteArray = null;
         var len:int = 0;
         var ref:int = this.readUInt29(input);
         if((ref & 1) == 0)
         {
            ba = this.instanceTable[ref >> 1];
         }
         else
         {
            len = ref >> 1;
            ba = new ByteArray();
            input.readBytes(ba,0,len);
            this.instanceTable.push(ba);
         }
         return ba;
      }
      
      private function readStringWithoutType(input:IDataInput) : String
      {
         var ref:int = this.readUInt29(input);
         if((ref & 1) == 0)
         {
            return this.stringTable[ref >> 1];
         }
         var len:int = ref >> 1;
         if(len == 0)
         {
            return "";
         }
         var str:String = input.readUTFBytes(len);
         this.stringTable.push(str);
         return str;
      }
      
      private function writeStringWithoutType(s:String, out:IDataOutput) : void
      {
         var bytes:ByteArray = null;
         var utfLen:int = 0;
         if(s.length == 0)
         {
            this.writeUInt29(1,out);
            return;
         }
         if(!this.stringByReference(s,out))
         {
            bytes = new ByteArray();
            bytes.writeUTFBytes(s);
            utfLen = bytes.length;
            this.writeUInt29(utfLen << 1 | 1,out);
            out.writeUTFBytes(s);
         }
      }
      
      private function writeUInt29(ref:int, out:IDataOutput) : void
      {
         if(ref < 128)
         {
            out.writeByte(ref);
         }
         else if(ref < 16384)
         {
            out.writeByte(ref >> 7 & 127 | 128);
            out.writeByte(ref & 127);
         }
         else if(ref < 2097152)
         {
            out.writeByte(ref >> 14 & 127 | 128);
            out.writeByte(ref >> 7 & 127 | 128);
            out.writeByte(ref & 127);
         }
         else if(ref < 1073741824)
         {
            out.writeByte(ref >> 22 & 127 | 128);
            out.writeByte(ref >> 15 & 127 | 128);
            out.writeByte(ref >> 8 & 127 | 128);
            out.writeByte(ref & 255);
         }
         else
         {
            throw new Error(resourceManager.getString("data","integerOutOfRange",[ref]));
         }
      }
   }
}

import flash.utils.ByteArray;
import flash.utils.IDataOutput;
import mx.data.utils.SerializationDescriptor;
import mx.data.utils.SerializationProxy;

class ProxyDataOutput implements IDataOutput
{
    
   
   private var _descriptor:SerializationDescriptor;
   
   private var _proxy:SerializationProxy;
   
   private var _out:IDataOutput;
   
   function ProxyDataOutput(proxy:SerializationProxy, out:IDataOutput, desc:SerializationDescriptor)
   {
      super();
      this._proxy = proxy;
      this._descriptor = desc;
      this._out = out;
   }
   
   public function writeObject(obj:*) : void
   {
      this._proxy.writeObject(obj,this._out,this._descriptor);
   }
   
   public function writeBoolean(value:Boolean) : void
   {
      this._out.writeBoolean(value);
   }
   
   public function writeByte(value:int) : void
   {
      this._out.writeByte(value);
   }
   
   public function writeBytes(bytes:ByteArray, offset:uint = 0, length:uint = 0) : void
   {
      this._out.writeBytes(bytes,offset,length);
   }
   
   public function writeDouble(value:Number) : void
   {
      this._out.writeDouble(value);
   }
   
   public function writeFloat(value:Number) : void
   {
      this._out.writeFloat(value);
   }
   
   public function writeInt(value:int) : void
   {
      this._out.writeInt(value);
   }
   
   public function writeMultiByte(value:String, charSet:String) : void
   {
      this._out.writeMultiByte(value,charSet);
   }
   
   public function writeShort(value:int) : void
   {
      this._out.writeInt(value);
   }
   
   public function writeUnsignedInt(value:uint) : void
   {
      this._out.writeUnsignedInt(value);
   }
   
   public function writeUTF(value:String) : void
   {
      this._out.writeUTF(value);
   }
   
   public function writeUTFBytes(value:String) : void
   {
      this._out.writeUTFBytes(value);
   }
   
   public function set endian(val:String) : void
   {
      this._out.endian = val;
   }
   
   public function get endian() : String
   {
      return this._out.endian;
   }
   
   public function set objectEncoding(val:uint) : void
   {
      this._out.objectEncoding = val;
   }
   
   public function get objectEncoding() : uint
   {
      return this._out.objectEncoding;
   }
}

import flash.utils.ByteArray;
import flash.utils.IDataInput;
import mx.data.utils.SerializationProxy;

class ProxyDataInput implements IDataInput
{
    
   
   private var _proxy:SerializationProxy;
   
   private var _input:IDataInput;
   
   function ProxyDataInput(proxy:SerializationProxy, input:IDataInput)
   {
      super();
      this._proxy = proxy;
      this._input = input;
   }
   
   public function readObject() : *
   {
      return this._proxy.readObject(this._input);
   }
   
   public function readBoolean() : Boolean
   {
      return this._input.readBoolean();
   }
   
   public function readByte() : int
   {
      return this._input.readByte();
   }
   
   public function readBytes(bytes:ByteArray, offset:uint = 0, length:uint = 0) : void
   {
      this._input.readBytes(bytes,offset,length);
   }
   
   public function readDouble() : Number
   {
      return this._input.readDouble();
   }
   
   public function readFloat() : Number
   {
      return this._input.readFloat();
   }
   
   public function readInt() : int
   {
      return this._input.readInt();
   }
   
   public function readMultiByte(length:uint, charSet:String) : String
   {
      return this._input.readMultiByte(length,charSet);
   }
   
   public function readShort() : int
   {
      return this._input.readInt();
   }
   
   public function readUnsignedByte() : uint
   {
      return this._input.readUnsignedByte();
   }
   
   public function readUnsignedInt() : uint
   {
      return this._input.readUnsignedInt();
   }
   
   public function readUnsignedShort() : uint
   {
      return this._input.readUnsignedShort();
   }
   
   public function readUTF() : String
   {
      return this._input.readUTF();
   }
   
   public function readUTFBytes(length:uint) : String
   {
      return this._input.readUTFBytes(length);
   }
   
   public function set endian(val:String) : void
   {
      this._input.endian = val;
   }
   
   public function get endian() : String
   {
      return this._input.endian;
   }
   
   public function set objectEncoding(val:uint) : void
   {
      this._input.objectEncoding = val;
   }
   
   public function get objectEncoding() : uint
   {
      return this._input.objectEncoding;
   }
   
   public function get bytesAvailable() : uint
   {
      return this._input.bytesAvailable;
   }
}

class TraitsInfo
{
    
   
   public var className:String;
   
   public var properties:Array;
   
   public var dynamic:Boolean;
   
   public var externalizable:Boolean;
   
   function TraitsInfo(className:String, properties:Array, dynamic:Boolean, externalizable:Boolean)
   {
      super();
      if(className == null)
      {
         className = "";
      }
      this.className = className;
      this.properties = properties;
      this.dynamic = dynamic;
      this.externalizable = externalizable;
   }
}
