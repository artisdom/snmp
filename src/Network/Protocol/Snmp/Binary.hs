{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE RecordWildCards         #-}
module Network.Protocol.Snmp.Binary where

import           Data.Serialize
import           Data.Typeable   (Typeable)
-- import Network.Protocol.Snmp ()
import           Data.Bits
import           Data.ByteString (ByteString)
import qualified Data.ByteString as B
import           Data.Word
-- import           Debug.Trace
import           Control.Monad
import           GHC.Generics
import           GHC.Int         (Int32, Int64)
import Data.List (unfoldr)

data Value = Integer Int32
           | BitString ByteString
           | OctetString ByteString
           | Null
           | OI [Word16]
           | IpAddress Word8 Word8 Word8 Word8
           | Counter32 Word32
           | Gauge32 Word32
           | TimeTicks Word32
           | Opaque ByteString
           | NsapAddress ByteString
           | Counter64 Word64
           | Uinteger32 Int32
           | NoSuchObject
           | NoSuchInstance
           | EndOfMibView
           deriving (Eq, Show, Ord, Generic)

table :: [(Integer, ByteString)]
table = zip [0 .. 10] $ map (B.drop 3 . encode) ([0 .. 10] :: [Word32])

type Tag = Word8 

class Tags a where
    tag :: a -> Tag

instance Tags Value where
    tag (Integer _) = 0x02
    tag (BitString _) = 0x03
    tag (OctetString _) = 0x04
    tag Null = 0x05
    tag (OI _) = 0x06
    tag IpAddress{} =  0x40
    tag (Counter32 _) = 0x41
    tag (Gauge32 _) = 0x42
    tag (TimeTicks _) = 0x43
    tag (Opaque _) = 0x44
    tag (NsapAddress _) = 0x45
    tag (Counter64 _) = 0x46
    tag (Uinteger32 _) = 0x47
    tag NoSuchObject = 0x80
    tag NoSuchInstance = 0x81
    tag EndOfMibView = 0x82

instance Tags Request where
    tag GetRequest{} = 0xa0
    tag GetNextRequest{} = 0xa1
    tag GetResponse{} = 0xa2
    tag SetRequest{} = 0xa3
    tag GetBulk{} = 0xa5
    tag Inform{} = 0xa6
    tag V2Trap{} = 0xa7
    tag Report{} = 0xa8

-- | Phantom type for version 1 (Header V2, PDU V2)
data V1
-- | Phantom type for version 2 (Header V2, PDU V2)
data V2
-- | Phantom type for version 3 (Header V3, PDU V3)
data V3

-- | Snmp version tag
data Version = Version1
             | Version2
             | Version3
             deriving (Eq, Ord, Show)

-- | Top level type, which describe snmp packet
data Packet where
  V2Packet :: Version -> Header V2 -> PDU V2 -> Packet
  V3Packet :: Version -> Header V3 -> PDU V3 -> Packet

deriving instance Show Packet
deriving instance Eq Packet

-- | Snmp header without version tag
data Header a where
  V2Header :: Community -> Header V2
  V3Header :: ID -> MaxSize -> Flag -> SecurityModel -> SecurityParameter -> Header V3

deriving instance Show (Header a)
deriving instance Eq (Header a)

-- | Snmp body
data PDU a where
  PDU :: Request -> Suite -> PDU V2
  ScopedPDU :: ContextEngineID -> ContextName -> PDU V2 -> PDU V3
  CryptedPDU :: ByteString -> PDU V3

deriving instance Show (PDU a)
deriving instance Eq (PDU a)

-- | Request id
newtype RequestId = RequestId Int32 deriving (Show, Eq, Ord)

-- | Error status
newtype ErrorStatus = ErrorStatus Integer deriving (Show, Eq, Ord)

-- | Error index
newtype ErrorIndex = ErrorIndex Integer deriving (Show, Eq, Ord)

-- | requests
data Request = GetRequest     { rid :: !RequestId, es :: !ErrorStatus, ei :: !ErrorIndex }
             | GetNextRequest { rid :: !RequestId, es :: !ErrorStatus, ei :: !ErrorIndex }
             | GetResponse    { rid :: !RequestId, es :: !ErrorStatus, ei :: !ErrorIndex }
             | SetRequest     { rid :: !RequestId, es :: !ErrorStatus, ei :: !ErrorIndex }
             | GetBulk        { rid :: !RequestId, es :: !ErrorStatus, ei :: !ErrorIndex }
             | Inform         { rid :: !RequestId, es :: !ErrorStatus, ei :: !ErrorIndex }
             | V2Trap         { rid :: !RequestId, es :: !ErrorStatus, ei :: !ErrorIndex }
             | Report         { rid :: !RequestId, es :: !ErrorStatus, ei :: !ErrorIndex }
             deriving (Show, Ord, Eq)

-- | Coupla oid -> value
data Coupla = Coupla { oid :: !Value, value :: !Value }
  deriving (Eq, Ord, Show)

-- | Variable bindings
newtype Suite = Suite [Coupla] deriving (Eq, Monoid, Show)

-- ** Types describing header

-- | (snmp2 only) Community for 2(1) version
newtype Community = Community ByteString
  deriving (Show, Eq, Ord)

-- | (snmp3 only) Message Identifier (like RequestId in PDU)
newtype ID = ID Int32
  deriving (Show, Eq, Ord)

-- | (snmp3 only) Message max size must be > 484
newtype MaxSize = MaxSize Int
  deriving (Show, Eq, Ord)

-- | (snmp3 only) rfc3412, type for create message flag
data PrivAuth = NoAuthNoPriv | AuthNoPriv | AuthPriv
  deriving (Show, Eq, Ord, Enum)

-- | (snmp3 only) rfc3412, as PrivAuth
type Reportable = Bool

-- | (snmp3 only) rfc3412, message flag
data Flag = Flag Reportable PrivAuth
  deriving (Show, Eq, Ord)

-- | (snmp3 only) rfc3412, security model
data SecurityModel = UserBasedSecurityModel
  deriving (Show, Eq)

-- | (snmp3 only) rfc3412, security parameter
data SecurityParameter = SecurityParameter
  { authoritiveEngineId      :: ByteString
  , authoritiveEngineBoots   :: Int32
  , authoritiveEngineTime    :: Int32
  , userName                 :: ByteString
  , authenticationParameters :: ByteString
  , privacyParameters        :: ByteString
  }
  deriving (Eq, Ord, Show)

-- | (snmp3 only) rfc3412, types for ScopedPDU
newtype ContextEngineID = ContextEngineID ByteString
  deriving (Show, Eq, Ord)

newtype ContextName = ContextName ByteString
  deriving (Show, Eq, Ord)

-- | some exception
newtype SnmpException = SnmpException ErrorStatus
    deriving (Typeable, Eq)

instance Show SnmpException where
    show (SnmpException (ErrorStatus 1)) = "tooBig"
    show (SnmpException (ErrorStatus 2)) = "noSuchName"
    show (SnmpException (ErrorStatus 3)) = "badValue"
    show (SnmpException (ErrorStatus 4)) = "readOnly"
    show (SnmpException (ErrorStatus 5)) = "genErr"
    show (SnmpException (ErrorStatus 6)) = "noAccess"
    show (SnmpException (ErrorStatus 7)) = "wrongType"
    show (SnmpException (ErrorStatus 8)) = "wrongLength"
    show (SnmpException (ErrorStatus 9)) = "wrongEncoding"
    show (SnmpException (ErrorStatus 10)) = "wrongValue"
    show (SnmpException (ErrorStatus 11)) = "noCreation"
    show (SnmpException (ErrorStatus 12)) = "inconsistentValue"
    show (SnmpException (ErrorStatus 13)) = "resourceUnavailable"
    show (SnmpException (ErrorStatus 14)) = "commitFailed"
    show (SnmpException (ErrorStatus 15)) = "undoFailed"
    show (SnmpException (ErrorStatus 16)) = "authorizationError"
    show (SnmpException (ErrorStatus 17)) = "notWritable"
    show (SnmpException (ErrorStatus 18)) = "inconsistentName"
    show (SnmpException (ErrorStatus 80)) = "General IO failure occured on the set request"
    show (SnmpException (ErrorStatus 81)) = "General SNMP timeout occured"
    show (SnmpException (ErrorStatus x)) = "Exception " ++ show x

-- | some universal getters, setters
class HasItem a where
    getHeader :: Packet -> Header a
    setHeader :: Header a -> Packet -> Packet
    getPDU :: Packet -> PDU a
    setPDU :: PDU a -> Packet -> Packet

-- | (snmp2 only) getters, setters for work with Header V2
class HasV2 a where
    getCommunity :: Header a -> Community
    setCommunity :: Community -> Header a -> Header a

-- | (snmp3 only) getters, setters for work with Header V3 and PDU V3.
class HasV3 a where
    getID :: Header a -> ID
    getMaxSize :: Header a -> MaxSize
    getFlag :: Header a -> Flag
    getSecurityModel :: Header a -> SecurityModel
    getSecurityParameter :: Header a -> SecurityParameter
    getAuthoritiveEngineId :: Header a -> ByteString
    getAuthoritiveEngineBoots :: Header a -> Int32
    getAuthoritiveEngineTime :: Header a -> Int32
    getUserName :: Header a -> ByteString
    getAuthenticationParameters :: Header a -> ByteString
    getPrivacyParameters :: Header a -> ByteString
    getContextEngineID :: PDU a -> ContextEngineID
    getContextName :: PDU a -> ContextName
    setID :: ID -> Header a -> Header a
    setMaxSize :: MaxSize -> Header a -> Header a
    setFlag :: Flag -> Header a -> Header a
    setSecurityModel :: SecurityModel -> Header a -> Header a
    setSecurityParameter :: SecurityParameter -> Header a -> Header a
    setAuthoritiveEngineId :: ByteString -> Header a -> Header a
    setAuthoritiveEngineBoots :: Int32 -> Header a -> Header a
    setAuthoritiveEngineTime :: Int32 -> Header a -> Header a
    setUserName :: ByteString -> Header a -> Header a
    setAuthenticationParameters :: ByteString -> Header a -> Header a
    setPrivacyParameters :: ByteString -> Header a -> Header a
    setContextEngineID :: ContextEngineID -> PDU a -> PDU a
    setContextName :: ContextName -> PDU a -> PDU a

-- | initial new object, like mempty for monoid
class Construct a where
    initial :: a

----------------------------------------------------------------------------------------
instance Construct (Version -> Packet) where
    initial Version3 = V3Packet Version3 initial initial
    initial Version2 = V2Packet Version2 initial initial
    initial Version1 = V2Packet Version1 initial initial

instance Construct (Header V3) where
    initial = V3Header (ID 0) (MaxSize 65007) (Flag False NoAuthNoPriv) UserBasedSecurityModel initial

instance Construct (Header V2) where
    initial = V2Header (Community "")

instance Construct (PDU V3) where
    initial = ScopedPDU (ContextEngineID "") (ContextName "") initial

instance Construct (PDU V2) where
    initial = PDU initial initial

instance Construct SecurityParameter where
    initial = SecurityParameter "" 0 0 "" "" ""

instance Construct Suite where
    initial = Suite []

instance Construct Request where
     initial = GetRequest (RequestId 0) (ErrorStatus 0) (ErrorIndex 0)
----------------------------------------------------------------------------------------
instance HasItem V2 where
    getHeader (V2Packet _ x _) = x
    getHeader _ = undefined
    setHeader h (V2Packet v _ x) = V2Packet v h x
    setHeader _ _ = undefined
    getPDU (V2Packet _ _ x) = x
    getPDU _ = undefined
    setPDU p (V2Packet v h _) = V2Packet v h p
    setPDU _ _ = undefined

instance HasItem V3 where
    getHeader (V3Packet _ x _) = x
    getHeader _ = undefined
    setHeader h (V3Packet v _ x) = V3Packet v h x
    setHeader _ _ = undefined
    getPDU (V3Packet _ _ x) = x
    getPDU _ = undefined
    setPDU p (V3Packet v h _) = V3Packet v h p
    setPDU _ _ = undefined

instance HasV2 V2 where
    getCommunity (V2Header c) = c
    setCommunity c (V2Header _) = V2Header c

instance HasV3 V3 where
    getID (V3Header i _ _ _ _) = i
    getMaxSize (V3Header _ i _ _ _) = i
    getFlag (V3Header _ _ i _ _) = i
    getSecurityModel (V3Header _ _ _ i _) = i
    getSecurityParameter (V3Header _ _ _ _ i) = i
    getAuthoritiveEngineId = authoritiveEngineId . getSecurityParameter
    getAuthoritiveEngineBoots = authoritiveEngineBoots . getSecurityParameter
    getAuthoritiveEngineTime = authoritiveEngineTime . getSecurityParameter
    getUserName = userName . getSecurityParameter
    getAuthenticationParameters = authenticationParameters . getSecurityParameter
    getPrivacyParameters = privacyParameters . getSecurityParameter
    getContextEngineID (ScopedPDU i _ _) = i
    getContextEngineID _ = undefined
    getContextName (ScopedPDU _ i _) = i
    getContextName _ = undefined
    setID i (V3Header _ a b c d) = V3Header i a b c d
    setMaxSize i (V3Header a _ b c d) = V3Header a i b c d
    setFlag i (V3Header a b _ c d) = V3Header a b i c d
    setSecurityModel i (V3Header a b c _ d) = V3Header a b c i d
    setSecurityParameter i (V3Header a b c d _) = V3Header a b c d i
    setAuthoritiveEngineId      i (V3Header a b c d f) = V3Header a b c d (f { authoritiveEngineId = i })
    setAuthoritiveEngineBoots   i (V3Header a b c d f) = V3Header a b c d (f { authoritiveEngineBoots = i })
    setAuthoritiveEngineTime    i (V3Header a b c d f) = V3Header a b c d (f { authoritiveEngineTime = i })
    setUserName                 i (V3Header a b c d f) = V3Header a b c d (f { userName = i })
    setAuthenticationParameters i (V3Header a b c d f) = V3Header a b c d (f { authenticationParameters = i })
    setPrivacyParameters        i (V3Header a b c d f) = V3Header a b c d (f { privacyParameters = i })
    setContextEngineID i (ScopedPDU _ b c) = ScopedPDU i b c
    setContextEngineID _ _ = undefined
    setContextName i (ScopedPDU a _ b) = ScopedPDU a i b
    setContextName _ _ = undefined

----------------------------------------------------------------------------------------
setIDP :: ID -> Packet -> Packet
setIDP x p =
  let header = getHeader p :: Header V3
      newHeader = setID x header
  in setHeader newHeader p

setMaxSizeP :: MaxSize -> Packet -> Packet
setMaxSizeP x p =
  let header = getHeader p :: Header V3
      newHeader = setMaxSize x header
  in setHeader newHeader p

setCommunityP :: Community -> Packet -> Packet
setCommunityP x p =
  let header = getHeader p :: Header V2
      newHeader = setCommunity x header
  in setHeader newHeader p

getEngineIdP :: Packet -> EngineId
getEngineIdP p =
  let header = getHeader p :: Header V3
  in getAuthoritiveEngineId header

setEngineIdP :: EngineId -> Packet -> Packet
setEngineIdP x p =
  let header = getHeader p :: Header V3
      newHeader = setAuthoritiveEngineId x header
  in setHeader newHeader p

getEngineBootsP :: Packet -> EngineBootId
getEngineBootsP p =
  let header = getHeader p :: Header V3
  in getAuthoritiveEngineBoots header

setEngineBootsP :: EngineBootId -> Packet -> Packet
setEngineBootsP x p =
  let header = getHeader p :: Header V3
      newHeader = setAuthoritiveEngineBoots x header
  in setHeader newHeader p

getEngineTimeP :: Packet -> Int32
getEngineTimeP p =
  let header = getHeader p :: Header V3
  in getAuthoritiveEngineTime header

setEngineTimeP :: Int32 -> Packet -> Packet
setEngineTimeP x p =
  let header = getHeader p :: Header V3
      newHeader = setAuthoritiveEngineTime x header
  in setHeader newHeader p

setReportableP :: Reportable -> Packet -> Packet
setReportableP r p =
  let header = getHeader p :: Header V3
      Flag _ a = getFlag header
      newHeader = setFlag (Flag r a) header
  in setHeader newHeader p

setPrivAuthP :: PrivAuth -> Packet -> Packet
setPrivAuthP x p =
  let header = getHeader p :: Header V3
      Flag r _ = getFlag header
      newHeader = setFlag (Flag r x) header
  in setHeader newHeader p

setUserNameP :: ByteString -> Packet -> Packet
setUserNameP x p =
  let header = getHeader p :: Header V3
      sp = getSecurityParameter header
      newHeader = setSecurityParameter (sp { userName = x }) header
  in setHeader newHeader p

setAuthenticationParametersP :: ByteString -> Packet -> Packet
setAuthenticationParametersP x p =
  let header = getHeader p :: Header V3
      sp = getSecurityParameter header
      newHeader = setSecurityParameter (sp { authenticationParameters = x }) header
  in setHeader newHeader p

getAuthenticationParametersP :: Packet -> ByteString
getAuthenticationParametersP p =
  let header = getHeader p :: Header V3
  in authenticationParameters (getSecurityParameter header)

setPrivParametersP :: ByteString -> Packet -> Packet
setPrivParametersP x p =
  let header = getHeader p :: Header V3
      sp = getSecurityParameter header
      newHeader = setSecurityParameter (sp { privacyParameters = x }) header
  in setHeader newHeader p

getPrivParametersP :: Packet -> ByteString
getPrivParametersP p =
  let header = getHeader p :: Header V3
  in privacyParameters $ getSecurityParameter header


getVersion :: Packet -> Version
getVersion (V2Packet v _ _) = v
getVersion (V3Packet v _ _) = v

getRid :: Packet -> RequestId
getRid (V2Packet _ _ (PDU r _)) = rid r
getRid (V3Packet _ _ (ScopedPDU _ _ (PDU r _))) = rid r
getRid _ = undefined

setRid :: RequestId -> Packet -> Packet
setRid r (V2Packet v h (PDU req s)) = V2Packet v h (PDU req { rid = r } s)
setRid r (V3Packet v h (ScopedPDU a b (PDU req s))) = V3Packet v h (ScopedPDU a b (PDU req { rid = r } s))
setRid _ _ = undefined

getErrorStatus :: Packet -> ErrorStatus
getErrorStatus (V2Packet _ _ (PDU r _)) = es r
getErrorStatus (V3Packet _ _ (ScopedPDU _ _ (PDU r _))) = es r
getErrorStatus _ = undefined

setErrorStatus :: ErrorStatus -> Packet -> Packet
setErrorStatus e (V2Packet v h (PDU req s)) = V2Packet v h (PDU req { es = e } s)
setErrorStatus e (V3Packet v h (ScopedPDU a b (PDU req s))) = V3Packet v h (ScopedPDU a b (PDU req { es = e } s))
setErrorStatus _ _ = undefined

getSuite :: Packet -> Suite
getSuite (V2Packet _ _ (PDU _ r)) = r
getSuite (V3Packet _ _ (ScopedPDU _ _ (PDU _ r))) = r
getSuite _ = undefined

setSuite :: Suite -> Packet -> Packet
setSuite s (V2Packet v h (PDU req _)) = V2Packet v h (PDU req s)
setSuite s (V3Packet v h (ScopedPDU a b (PDU req _))) = V3Packet v h (ScopedPDU a b (PDU req s))
setSuite _ _ = undefined

getRequest :: Packet -> Request
getRequest (V2Packet _ _ (PDU r _)) = r
getRequest (V3Packet _ _ (ScopedPDU _ _ (PDU r _))) = r
getRequest _ = undefined

setRequest :: Request -> Packet -> Packet
setRequest req (V2Packet v h (PDU _ s)) = V2Packet v h (PDU req s)
setRequest req (V3Packet v h (ScopedPDU a b (PDU _ s))) = V3Packet v h (ScopedPDU a b (PDU req s))
setRequest _ _ = undefined
----------------------------------------------------------------------------------------

type EngineBootId = Int32
type PrivacyParameter = ByteString
type EngineId = ByteString
type Salt = ByteString
type Encrypted = ByteString
type Raw = ByteString
type Rand32 = Int32
type Rand64 = Int64

newtype Size = Size Int deriving (Eq, Show, Ord)

instance Serialize Size where
    put (Size i)
      | i >= 0 && i <= 0x7f         = mapM_ putWord8 [fromIntegral i]
      | i < 0     = error "8"
      | otherwise = mapM_ putWord8 $ lenbytes : lw
      where
      lw       = bytesOfUInt $ fromIntegral i
      lenbytes = fromIntegral (length lw .|. 0x80)
    get = do
      l1 <- fromIntegral <$> getWord8
      if testBit l1 7
         then case clearBit l1 7 of
                   0   -> return $ Size 0
                   len -> do
                       lw <- getBytes len
                       return $ Size $ uintbs lw
         else
             return $ Size l1
      where
      {- uintbs return the unsigned int represented by the bytes -}
      uintbs = B.foldl (\acc n -> (acc `shiftL` 8) + fromIntegral n) 0

putLength :: Putter Int
putLength x = put (Size x)

getLength :: Get Int
getLength = do
    Size i <- get
    return i

putTag :: Value -> Put
putTag = putWord8 . tag

type ErrorCode = Int

getTag :: Tag -> ErrorCode -> Get ()
getTag x e = do
    t <- getWord8
    if t /= x 
       then error $ show e
       else return ()

putIntegral :: Integral a => Value -> a -> Put
putIntegral v a = do
    putTag v
    let bytes = bytesOfInt (fromIntegral a)
        l = fromIntegral $ length bytes
    put (Size l)
    mapM_ putWord8 bytes

putIntegralU :: Integral a => Value -> a -> Put
putIntegralU v a = do
    putTag v
    let bytes = bytesOfUInt (fromIntegral a)
        l = fromIntegral $ length bytes
    put (Size l)
    mapM_ putWord8 bytes

putBS :: Value -> ByteString -> Put
putBS v bs = do
    putTag v
    let l = fromIntegral $ B.length bs
    put (Size l)
    putByteString bs

instance Serialize Value where
    put v@(Integer i) = putIntegral v i
    put v@(BitString bs) = putBS v bs
    put v@(OctetString bs) = putBS v bs
    put Null = do
        putTag Null
        putWord8 0
    put v@(OI oids) =
        case oids of
             (oid1:oid2:suboids) -> do
                 let eoidclass = fromIntegral (oid1 * 40 + oid2)
                 putTag v
                 let bs = B.cons eoidclass $ B.concat $ map encode' suboids
                 put (Size (B.length bs))
                 putByteString bs
             _ -> error "put oi"
        where
        encode' x | x == 0 = B.singleton 0
                 | otherwise = putVarEncodingIntegral x
    put v@(IpAddress a b c d) = do
        putTag v
        putWord8 4
        putWord8 a >> putWord8 b >> putWord8 c >> putWord8 d
    put v@(Counter32 i) = putIntegralU v i
    put v@(Gauge32 i) = putIntegralU v i
    put v@(TimeTicks i) = putIntegralU v i
    put v@(Opaque bs) = putBS v bs
    put v@(NsapAddress bs) = putBS v bs
    put v@(Counter64 i) = putIntegral v i
    put v@(Uinteger32 i) = putIntegralU v i
    put v@NoSuchObject = do
        putTag v
        putWord8 0
    put v@NoSuchInstance = do
        putTag v
        putWord8 0
    put v@EndOfMibView = do
        putTag v
        putWord8 0
    get = do
        t <- getWord8
        case t of
             0x02 -> do
                 Size l <- get
                 Integer . fromIntegral . snd . intOfBytes <$> getBytes (fromIntegral l)
             0x03 -> do
                 Size l <- get
                 BitString <$> getByteString l
             0x04 -> do
                 Size l <- get
                 OctetString <$> getByteString l
             0x05 -> do
                 Size _ <- get
                 0 <- getWord8
                 return Null
             0x06 -> do
                 Size l <- get
                 bs <- getByteString (fromIntegral l)
                 let (x:xs) = B.unpack bs
                     groupOID :: [Word8] -> [Word16]
                     groupOID = map (foldl (\acc n -> (acc `shiftL` 7) + fromIntegral n) 0) . groupSubOID
                     groupSubOIDHelper [] = Nothing
                     groupSubOIDHelper s = Just $ spanSubOIDbound s
                     groupSubOID :: [Word8] -> [[Word8]]
                     groupSubOID = unfoldr groupSubOIDHelper
                     spanSubOIDbound [] = ([], [])
                     spanSubOIDbound (a:as) = if testBit a 7 then (clearBit a 7 : ys, zs) else ([a], as)
                       where (ys, zs) = spanSubOIDbound as
                 return $ OI (fromIntegral (x `div` 40) : fromIntegral (x `mod` 40) : groupOID xs)
             0x40 -> do
                 Size _ <- get
                 IpAddress <$> getWord8 <*> getWord8 <*> getWord8 <*> getWord8
             0x41 -> do
                 Size l <- get
                 Counter32 . fromIntegral . snd . uintOfBytes <$> getBytes (fromIntegral l)
             0x42 -> do
                 Size l <- get
                 Gauge32 . fromIntegral . snd . uintOfBytes <$> getBytes (fromIntegral l)
             0x43 -> do
                 Size l <- get
                 TimeTicks . fromIntegral . snd . uintOfBytes <$> getBytes (fromIntegral l)
             0x44 -> do
                 Size l <- get
                 Opaque <$> getByteString (fromIntegral l)
             0x45 -> do
                 Size l <- get
                 NsapAddress <$> getByteString (fromIntegral l)
             0x46 -> do
                 Size l <- get
                 Counter64 . fromIntegral . snd . uintOfBytes <$> getBytes (fromIntegral l)
             0x47 -> do
                 Size l <- get
                 Uinteger32 . fromIntegral . snd . uintOfBytes <$> getBytes (fromIntegral l)
             0x80 -> void getWord8 *> return NoSuchObject
             0x81 -> void getWord8 *> return NoSuchInstance
             0x82 -> void getWord8 *> return EndOfMibView
             _ -> error "9"


{- | uintOfBytes returns the number of bytes and the unsigned integer represented by the bytes -}
uintOfBytes :: ByteString -> (Int, Integer)
uintOfBytes b = (B.length b, B.foldl (\acc n -> (acc `shiftL` 8) + fromIntegral n) 0 b)

--bytesOfUInt i = B.unfoldr (\x -> if x == 0 then Nothing else Just (fromIntegral (x .&. 0xff), x `shiftR` 8)) i
bytesOfUInt :: Integer -> [Word8]
bytesOfUInt x = reverse (list x)
    where list i = if i <= 0xff then [fromIntegral i] else (fromIntegral i .&. 0xff) : list (i `shiftR` 8)

{- | intOfBytes returns the number of bytes in the list and
   the represented integer by a two's completement list of bytes -}
intOfBytes :: ByteString -> (Int, Integer)
intOfBytes b
    | B.length b == 0   = (0, 0)
    | otherwise         = (len, if isNeg then -(maxIntLen - v + 1) else v)
    where
        (len, v)  = uintOfBytes b
        maxIntLen = 2 ^ (8 * len) - 1
        isNeg     = testBit (B.head b) 7

{- | bytesOfInt convert an integer into a two's completemented list of bytes -}
bytesOfInt :: Integer -> [Word8]
bytesOfInt i
    | i > 0      = if testBit (head uints) 7 then 0 : uints else uints
    | i == 0     = [0]
    | otherwise  = if testBit (head nints) 7 then nints else 0xff : nints
    where
        uints = bytesOfUInt (abs i)
        nints = reverse $ plusOne $ reverse $ map complement uints
        plusOne []     = [1]
        plusOne (x:xs) = if x == 0xff then 0 : plusOne xs else (x+1) : xs

putVarEncodingIntegral :: (Bits i, Integral i) => i -> ByteString
putVarEncodingIntegral i = B.reverse $ B.unfoldr genOctets (i,True)
    where genOctets (x,first)
            | x > 0     =
                let out = fromIntegral (x .&. 0x7F) .|. (if first then 0 else 0x80) in
                Just (out, (shiftR x 7, False))
            | otherwise = Nothing

instance Serialize Version where
    put Version1 = put (Integer 0)
    put Version2 = put (Integer 1)
    put Version3 = put (Integer 3)
    get = do
        Integer x <- get
        case x of
             0 -> return Version1
             1 -> return Version2
             3 -> return Version3
             _ -> error "10"

instance Serialize Community where
    put (Community bs) = put (OctetString bs)
    get = do
        OctetString bs <- get
        return (Community bs)

instance Serialize (Header V2) where
    put (V2Header c) = put c
    get = do
        c <- get
        return $ V2Header c

instance Serialize ID where
    put (ID x) = put (Integer x)
    get = do
        Integer x <- get
        return $ ID x
instance Serialize MaxSize where
    put (MaxSize x) = put (Integer $ fromIntegral x)
    get = do
        Integer x <- get
        return $ MaxSize $ fromIntegral x
instance Serialize Flag where
    put (Flag r pa) = do
        let zero = zeroBits :: Word8
            reportable = if r then setBit zero 0 else zero
            privauth = case pa of
                            NoAuthNoPriv -> zero
                            AuthNoPriv -> setBit zero 2
                            AuthPriv -> setBit zero 1 .|. setBit zero 2
            flag = reportable .|. privauth
        put $ OctetString (B.pack [flag]) 
    get = do
        OctetString f <- get
        let [w] = B.unpack f
        return $ case (testBit w 0, testBit w 1) of
                      (True, True) -> Flag (testBit w 2) AuthPriv
                      (False, False) -> Flag (testBit w 2) NoAuthNoPriv
                      (True, False) -> Flag (testBit w 2) AuthNoPriv
                      _ -> error "10" -- SnmpException 10
instance Serialize SecurityModel where
    put UserBasedSecurityModel = put (Integer 3)
    get = do
        Integer x <- get
        case x of
             3 -> return UserBasedSecurityModel
             _ -> error "7" -- SnmpException 7

instance Serialize SecurityParameter where
    put SecurityParameter{..} = do
        putTag (OctetString "")
        putNested putLength (putWord8 0x30 >> putNested putLength putSecurityParameter)
        where
        putSecurityParameter = do
            put (OctetString authoritiveEngineId)
            put (Integer $ fromIntegral authoritiveEngineBoots)
            put (Integer $ fromIntegral authoritiveEngineTime)
            put (OctetString userName)
            put (OctetString authenticationParameters)
            put (OctetString privacyParameters)
    get = do
        getTag (tag (OctetString "")) 9
        getNested getLength (getTag 0x30 9 >> getNested getLength getSecurityParameter')
      where
      getSecurityParameter' :: Get SecurityParameter
      getSecurityParameter' = do
          OctetString authoritiveEngineId' <- get
          Integer authoritiveEngineBoots' <- get
          Integer authoritiveEngineTime' <- get
          OctetString userName' <- get
          OctetString authenticationParameters' <- get
          OctetString privacyParameters' <- get
          return $ SecurityParameter authoritiveEngineId' 
                                     (fromIntegral authoritiveEngineBoots')
                                     (fromIntegral authoritiveEngineTime')
                                     userName'
                                     authenticationParameters'
                                     privacyParameters'


instance Serialize (Header V3) where
    put (V3Header iD maxSize flag securityModel securityParameter) = do
        putWord8 0x30
        putNested putLength putHeader
        put securityParameter
        where
        putHeader = do
            put iD
            put maxSize
            put flag
            put securityModel
    get = do
        getTag 0x30 9
        (iD, maxSize, flag, securityModel) <- getNested getLength getHeader' 
        securityParameter <- get
        return $ V3Header iD maxSize flag securityModel securityParameter
        where
        getHeader' = (,,,) <$> get <*> get <*> get <*> get

instance Serialize RequestId where
    put (RequestId rid) = put (Integer $ fromIntegral rid)
    get = do
        Integer i <- get
        return $ RequestId $ fromIntegral i

instance Serialize ErrorStatus where
    put (ErrorStatus es) = put (Integer $ fromIntegral es)
    get = do
        Integer i <- get
        return $ ErrorStatus $ fromIntegral i

instance Serialize ErrorIndex where
    put (ErrorIndex ei) = put (Integer $ fromIntegral ei)
    get = do
        Integer i <- get
        return $ ErrorIndex $ fromIntegral i

instance Serialize Suite where
    put (Suite bs) = putWord8 0x30 >> putNested putLength (mapM_ put bs)
    get = do
        getTag 0x30 9
        Suite <$> getNested getLength (getSuite' [])
        where
        getSuite' xs = do
            check <- isEmpty
            if check 
               then return xs
               else do
                   coupla <- get
                   getSuite' (coupla : xs)

instance Serialize Coupla where
    put Coupla{..} = putWord8 0x30 >> putNested putLength (put oid >> put value)
    get = do
        getTag 0x30 9
        getNested getLength (Coupla <$> get <*> get)

instance Serialize (PDU V2) where
    put (PDU request suite) = do
        putWord8 (tag request)
        putNested putLength (put (rid request) >> put (es request) >> put (ei request) >> put suite)
    get = do
        t <- getWord8
        let request = case t of
                           0xa0 -> GetRequest 
                           0xa1 -> GetNextRequest 
                           0xa2 -> GetResponse
                           0xa3 -> SetRequest 
                           0xa5 -> GetBulk
                           0xa6 -> Inform
                           0xa7 -> V2Trap
                           0xa8 -> Report
                           _ -> error "9"
        getNested getLength (PDU <$> (request <$> get <*> get <*> get) <*> get)

