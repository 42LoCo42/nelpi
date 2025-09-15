import contextlib
import importlib.resources as resources
import json
import logging
from glob import glob
from math import ceil
from re import Match, match

import joblib
import spacy
from gensim.corpora import Dictionary
from gensim.models import LdaMulticore
from joblib import Parallel, delayed
from spacy.language import Language
from spacy.tokens import Doc
from tqdm import tqdm

NLP: Language = spacy.load("de_core_news_sm", disable=["ner", "parser"])

def main() -> None:
    formatter = logging.Formatter("%(asctime)s [%(levelname)-4s] %(message)s")

    handler = logging.StreamHandler()
    handler.setFormatter(formatter)

    logger = logging.getLogger("nelpi")
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    info = logger.info

    datasets: list[str] = sorted(glob(str(
        resources.files(__name__) / "datasets/*.json")))
    raw_entries: list[str] = []

    info("Loading entries...")
    for path in datasets:
        mat: Match[str] | None = match(r".*/([^/]+)\.json$", path)
        assert mat != None
        name: str = mat[1]

        data: list[str] = json.load(open(path, "r"))
        raw_entries += data
        info(f"  Loaded {len(data):>5} entries from dataset '{name}'")

    info(f"{len(raw_entries)} entries in total!")

    entries: list[list[str]] = preprocess_parallel(raw_entries)
    dictionary: Dictionary = Dictionary(tqdm(entries, desc="Dictionary   "))
    corpus = [dictionary.doc2bow(e) for e in tqdm(entries, desc="Corpus       ")]

    info("Building LDA model...")
    lda_model: LdaMulticore = LdaMulticore(
        corpus     = corpus,
        id2word    = dictionary,
        num_topics = 10, # TODO how many topics do we want?
        passes     = 10, # TODO is this important?
    )

    info("=" * 80)
    for i, topic in lda_model.print_topics():
        info(f"Topic {i}: {topic}")

# https://freedium.cfd/https://medium.com/data-science/turbo-charge-your-spacy-nlp-pipeline-551435b664ad
def chunker(list, chunksize):
    return (list[pos : pos + chunksize] for pos in range(0, len(list), chunksize))

def flatten(list_of_lists):
    "Flatten a list of lists to a combined list"
    return [item for sublist in list_of_lists for item in sublist]

def lemmatize_pipe(doc: Doc) -> list[str]:
    return [
        token.lemma_.lower()
        for token in doc
        if not any([
            token.is_punct,
            token.is_space,
            token.is_stop,
        ])
    ]

def process_chunk(texts) -> list[list[str]]:
    preproc_pipe: list[list[str]] = []
    for doc in NLP.pipe(texts):
        preproc_pipe.append(lemmatize_pipe(doc))
    return preproc_pipe

def preprocess_parallel(texts, chunksize=100) -> list[list[str]]:
    with tqdm_joblib(tqdm(desc="Preprocessing", total=ceil(len(texts) / chunksize))):
        executor = Parallel(n_jobs=-1, backend="multiprocessing")
        do = delayed(process_chunk)
        tasks = (do(chunk) for chunk in chunker(texts, chunksize=chunksize))
        result = executor(tasks)
        return flatten(result)

# https://stackoverflow.com/a/58936697
@contextlib.contextmanager
def tqdm_joblib(tqdm_object):
    """Context manager to patch joblib to report into tqdm progress bar given as argument"""

    class TqdmBatchCompletionCallback(joblib.parallel.BatchCompletionCallBack):
        def __call__(self, *args, **kwargs):
            tqdm_object.update(n=self.batch_size)
            return super().__call__(*args, **kwargs)

    old_batch_callback = joblib.parallel.BatchCompletionCallBack
    joblib.parallel.BatchCompletionCallBack = TqdmBatchCompletionCallback
    try:
        yield tqdm_object
    finally:
        joblib.parallel.BatchCompletionCallBack = old_batch_callback
        tqdm_object.close()

# Local Variables:
# apheleia-mode: nil
# lsp-inlay-hint-enable: nil
# End:
