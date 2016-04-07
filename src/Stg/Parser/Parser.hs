-- | A parser for the STG language, modeled after the decription in the 1992
-- paper with a couple of minor differences:
--
--   * () instead of {}
--   * Comment syntax like in Haskell
module Stg.Parser.Parser where



import           Control.Applicative
import           Control.Monad
import           Data.Bifunctor
import qualified Data.Map              as M
import           Data.Text             (Text)
import qualified Data.Text             as T
import           Text.Megaparsec       ((<?>))
import qualified Text.Megaparsec       as P
import qualified Text.Megaparsec.Char  as C
import qualified Text.Megaparsec.Lexer as L
import           Text.Megaparsec.Text

import           Stg.Language



--------------------------------------------------------------------------------
-- Lexing

spaceConsumer :: Parser ()
spaceConsumer = L.space (P.some P.spaceChar *> pure ())
                        (L.skipLineComment "--")
                        (L.skipBlockComment "{-" "-}")

lexeme :: Parser a -> Parser a
lexeme = L.lexeme spaceConsumer

symbol :: String -> Parser ()
symbol s = void (lexeme (C.string s)) <?> s

semicolonTok :: Parser ()
semicolonTok = symbol ";"

commaTok :: Parser ()
commaTok = symbol ","

letTok :: Parser (Binds -> Expr -> Expr)
letTok = P.try (lexeme (C.string "let"    *> C.spaceChar) *> pure (Let NonRecursive))
     <|> P.try (lexeme (C.string "letrec" *> C.spaceChar) *> pure (Let Recursive))

inTok :: Parser ()
inTok = symbol "in"

caseTok :: Parser (Expr -> Alts -> Expr)
caseTok = lexeme (C.string "case" *> C.spaceChar) *> pure Case

ofTok :: Parser ()
ofTok = symbol "of"

assignTok :: Parser ()
assignTok = symbol "="

varTok :: Parser Var
varTok = lexeme p <?> "variable"
  where
    p = liftA2 (\x xs -> Var (T.pack (x:xs)))
                P.lowerChar
                (P.many (P.alphaNumChar <|> P.char '\''))

conTok :: Parser Constr
conTok = lexeme p <?> "constructor"
  where
    p = liftA2 (\x xs -> Constr (T.pack (x:xs)))
                P.upperChar
                (P.many (P.alphaNumChar <|> P.char '\''))

defNotBoundTok :: Parser (Expr -> DefaultAlt)
defNotBoundTok = symbol "default" *> pure DefaultNotBound

arrowTok :: Parser ()
arrowTok = symbol "->"

hashTok :: Parser ()
hashTok = symbol "#"

openParenthesisTok :: Parser ()
openParenthesisTok = symbol "("

closeParenthesisTok :: Parser ()
closeParenthesisTok = symbol ")"

parenthesized :: Parser a -> Parser a
parenthesized = P.between openParenthesisTok closeParenthesisTok

updateFlagTok :: Parser UpdateFlag
updateFlagTok = lexeme (P.char '\\' *> flag) <?> help
  where
    flag = C.char 'u' *> pure Update <|> C.char 'n' *> pure NoUpdate
    help = "\\u (update), \\n (no update)"

--------------------------------------------------------------------------------
-- Parsing

parse :: Text -> Either String Program
parse = first show . P.runParser stgLanguage "(string)"

stgLanguage :: Parser Program
stgLanguage = spaceConsumer *> fmap Program binds <* P.eof

binds :: Parser Binds
binds = fmap (Binds . M.fromList) (P.sepBy binding semicolonTok)
  where
    binding :: Parser (Var, LambdaForm)
    binding = (,) <$> varTok <* assignTok <*> lambdaForm


lambdaForm :: Parser LambdaForm
lambdaForm = LambdaForm
         <$> vars
         <*> updateFlagTok
         <*> vars
         <*  arrowTok
         <*> expr
         <?> "lambda form"

expr :: Parser Expr
expr = P.choice [let', case', appF, appC, appP, lit]
  where
    let' = letTok
       <*> (binds <?> "list of free variables")
       <*  inTok
       <*> (expr <?> "body")
       <?> "let"
    case' = caseTok
        <*> (expr <?> "case scrutinee")
        <*  ofTok
        <*> alts
        <?> "case"
    appF = AppF
        <$> varTok
        <*> atoms
        <?> "function application"
    appC = AppC
        <$> conTok
        <*> atoms
        <?> "constructor application"
    appP = AppP
        <$> primOp
        <*> atom
        <*> atom
        <?> "primitive function application"
    lit = Lit
        <$> literal
        <?> "literal"

alts :: Parser Alts
alts = algebraic <|> primitive
    <?> "case alternatives"
  where
    algebraic = Algebraic <$> algebraicAlts
    primitive = Primitive <$> primitiveAlts

algebraicAlts :: Parser AlgebraicAlts
algebraicAlts = AlgebraicAlts
            <$> P.sepEndBy algebraicAlt semicolonTok
            <*> defaultAlt
            <?> "algebraic alternatives"

primitiveAlts :: Parser PrimitiveAlts
primitiveAlts = PrimitiveAlts
            <$> P.sepEndBy primitiveAlt semicolonTok
            <*> defaultAlt
            <?> "primitive alternatives"

algebraicAlt :: Parser AlgebraicAlt
algebraicAlt = AlgebraicAlt <$> conTok <*> vars <* arrowTok <*> expr
    <?> "algebraic alternative"

primitiveAlt :: Parser PrimitiveAlt
primitiveAlt = PrimitiveAlt <$> literal <* arrowTok <*> expr
    <?> "primitive alternative"

defaultAlt :: Parser DefaultAlt
defaultAlt = P.try defNotBoundTok <* arrowTok <*>expr
         <|> DefaultBound <$> varTok <* arrowTok <*> expr
         <?> "default alternative"

literal :: Parser Literal
literal = (Literal . fromInteger) <$> L.integer <* hashTok
    <?> "integer literal"

primOp :: Parser PrimOp
primOp = P.try (P.choice choices <* hashTok)
    <?> "primitive function"
  where
    choices = [ P.char '+' *> pure Add
              , P.char '-' *> pure Sub
              , P.char '*' *> pure Mul
              , P.char '/' *> pure Div
              , P.char '%' *> pure Mod ]

vars :: Parser [Var]
vars = parenthesized (P.sepBy varTok commaTok)
    <?> "variables"

atoms :: Parser [Atom]
atoms = parenthesized (P.sepBy atom commaTok)
    <?> "atoms"

atom :: Parser Atom
atom = AtomVar <$> varTok
   <|> AtomLit <$> literal
   <?> "atom"
