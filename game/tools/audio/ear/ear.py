import sys
import os
import json
import glob

def log(msg):
    print(msg)
    sys.stdout.flush()

def load_intents(intents_path):
    with open(intents_path, encoding='utf-8') as f:
        return json.load(f)

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--dir', required=True)
    parser.add_argument('--intents', required=True)
    parser.add_argument('--out-md', required=True)
    parser.add_argument('--out-json', required=True)
    args = parser.parse_args()

    log('loading torch/transformers (this can take a while on first run)')
    import torch
    from transformers import pipeline

    log('loading zero-shot audio classifier: laion/clap-htsat-unfused')
    clap = pipeline(task='zero-shot-audio-classification', model='laion/clap-htsat-unfused')

    log('loading audioset tagger: MIT/ast-finetuned-audioset-10-10-0.4593')
    ast = pipeline(task='audio-classification', model='MIT/ast-finetuned-audioset-10-10-0.4593')

    intents = load_intents(args.intents)

    wav_files = sorted(glob.glob(os.path.join(args.dir, '*.wav')))
    results = {}

    for wav_path in wav_files:
        name = os.path.basename(wav_path)
        log('processing ' + name)

        entry = intents.get(name)
        if entry is None:
            log('WARN: no intent entry for ' + name + ', skipping CLAP compare')
            ast_out = ast(wav_path, top_k=10)
            results[name] = {
                'audioset_top10': ast_out,
                'clap': None,
                'warn': True,
                'reason': 'no intents.json entry',
            }
            continue

        intent_text = entry['intent']
        confusions = entry['confusions']
        candidate_labels = [intent_text] + confusions

        clap_out = clap(wav_path, candidate_labels=candidate_labels)
        ast_out = ast(wav_path, top_k=10)

        top_label = clap_out[0]['label']
        is_intent_top = (top_label == intent_text)

        results[name] = {
            'intent': intent_text,
            'clap_ranking': clap_out,
            'audioset_top10': ast_out,
            'intent_is_top': is_intent_top,
            'warn': (not is_intent_top),
        }

        status = 'OK' if is_intent_top else 'WARN'
        log('  ' + status + ' top=' + top_label)

    with open(args.out_json, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    write_report(results, args.out_md)
    log('done. wrote ' + args.out_md + ' and ' + args.out_json)

def write_report(results, out_md_path):
    lines = []
    lines.append('# LISTEN REPORT')
    lines.append('')
    lines.append('Models: laion/clap-htsat-unfused (zero-shot CLAP), MIT/ast-finetuned-audioset-10-10-0.4593 (AudioSet top-10)')
    lines.append('')
    lines.append('| file | intent | clap top label | clap top score | intent rank | warn |')
    lines.append('|---|---|---|---|---|---|')
    for name in sorted(results.keys()):
        r = results[name]
        if r.get('clap_ranking') is None:
            lines.append('| ' + name + ' | (no intent entry) | - | - | - | WARN |')
            continue
        ranking = r['clap_ranking']
        top = ranking[0]
        intent_text = r['intent']
        rank = None
        for i, item in enumerate(ranking):
            if item['label'] == intent_text:
                rank = i + 1
                break
        warn_str = 'WARN' if r['warn'] else 'ok'
        lines.append('| ' + name + ' | ' + intent_text + ' | ' + top['label'] + ' | ' + str(round(top['score'], 4)) + ' | ' + str(rank) + ' | ' + warn_str + ' |')

    lines.append('')
    lines.append('## AudioSet top-10 per file')
    lines.append('')
    for name in sorted(results.keys()):
        r = results[name]
        lines.append('### ' + name)
        for item in r['audioset_top10']:
            lines.append('- ' + item['label'] + ': ' + str(round(item['score'], 4)))
        lines.append('')

    with open(out_md_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))

if __name__ == '__main__':
    main()
