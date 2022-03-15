{-# LANGUAGE OverloadedStrings #-}

module UntypedPlutusCore.Parser
    ( parse
    , term
    , program
    , parseTerm
    , parseProgram
    , parseScoped
    , Parser
    , SourcePos
    ) where

import Prelude hiding (fail)

import Control.Monad.Except (MonadError, (<=<))

import PlutusCore qualified as PLC
import PlutusCore.Error (AsParserError)
import PlutusPrelude (through)
import Text.Megaparsec hiding (ParseError, State, parse)
import UntypedPlutusCore.Check.Uniques (checkProgram)
import UntypedPlutusCore.Core.Type qualified as UPLC
import UntypedPlutusCore.Rename (Rename (rename))

import Data.ByteString.Lazy (ByteString)
import PlutusCore.Parser hiding (parseProgram, parseTerm)
import PlutusCore.Quote (MonadQuote)

-- Parsers for UPLC terms

-- | A parsable UPLC term.
type PTerm = UPLC.Term PLC.Name PLC.DefaultUni PLC.DefaultFun SourcePos

conTerm :: Parser PTerm
conTerm = inParens $ UPLC.Constant <$> wordPos "con" <*> constant

builtinTerm :: Parser PTerm
builtinTerm = inParens $ UPLC.Builtin <$> wordPos "builtin" <*> builtinFunction

varTerm :: Parser PTerm
varTerm = UPLC.Var <$> getSourcePos <*> name

lamTerm :: Parser (UPLC.Term PLC.Name PLC.DefaultUni PLC.DefaultFun  SourcePos)
lamTerm = inParens $ UPLC.LamAbs <$> wordPos "lam" <*> name <*> term

appTerm :: Parser (UPLC.Term PLC.Name PLC.DefaultUni PLC.DefaultFun  SourcePos)
appTerm = inBrackets $ UPLC.Apply <$> getSourcePos <*> term <*> term

delayTerm :: Parser PTerm
delayTerm = inParens $ UPLC.Delay <$> wordPos "delay" <*> term

forceTerm :: Parser PTerm
forceTerm = inParens $ UPLC.Force <$> wordPos "force" <*> term

errorTerm
    :: Parser PTerm
errorTerm = inParens $ UPLC.Error <$> wordPos "error"

-- | Parser for all UPLC terms.
term :: Parser PTerm
term = choice $ map try [
    conTerm
    , builtinTerm
    , varTerm
    , lamTerm
    , appTerm
    , delayTerm
    , forceTerm
    , errorTerm
    ]

-- | Parser for UPLC programs.
program :: Parser (UPLC.Program PLC.Name PLC.DefaultUni PLC.DefaultFun SourcePos)
program = whitespace >> do
    prog <- inParens $ UPLC.Program <$> wordPos "program" <*> version <*> term
    notFollowedBy anySingle
    return prog

-- | Parse a UPLC term. The resulting program will have fresh names. The underlying monad must be capable
-- of handling any parse errors.
parseTerm :: (AsParserError e, MonadError e m, MonadQuote m) => ByteString -> m PTerm
parseTerm = parseGen term

-- | Parse a UPLC program. The resulting program will have fresh names. The underlying monad must be capable
-- of handling any parse errors.
parseProgram :: (AsParserError e, MonadError e m, MonadQuote m) => ByteString -> m (UPLC.Program PLC.Name PLC.DefaultUni PLC.DefaultFun SourcePos)
parseProgram = parseGen program

-- | Parse and rewrite so that names are globally unique, not just unique within
-- their scope.
parseScoped ::
    (AsParserError e, PLC.MonadQuote m, MonadError e m, PLC.AsUniqueError e SourcePos)
    => ByteString
    -> m (UPLC.Program PLC.Name PLC.DefaultUni PLC.DefaultFun SourcePos)
-- don't require there to be no free variables at this point, we might be parsing an open term
parseScoped = through (checkProgram (const True)) <=< rename <=< parseProgram
