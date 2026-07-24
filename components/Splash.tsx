"use client";

import { useEffect, useState } from "react";
import { motion, useReducedMotion } from "framer-motion";
import InterlockMark from "./InterlockMark";

/**
 * The launch moment. Two circles settle into one before the app appears —
 * WE's whole thesis in a second and a half. Shown on every open.
 */
export default function Splash({ onDone }: { onDone: () => void }) {
  const reduceMotion = useReducedMotion();
  const [overlap, setOverlap] = useState<"apart" | "interlocked">("apart");

  useEffect(() => {
    const settle = setTimeout(() => setOverlap("interlocked"), reduceMotion ? 0 : 450);
    const done = setTimeout(onDone, reduceMotion ? 700 : 1750);
    return () => {
      clearTimeout(settle);
      clearTimeout(done);
    };
  }, [onDone, reduceMotion]);

  return (
    <motion.div
      className="flex h-full flex-col items-center justify-center"
      initial={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.5 }}
    >
      <InterlockMark size={96} overlap={overlap} />
      <motion.span
        className="mt-8 font-serif text-2xl tracking-[0.3em]"
        initial={reduceMotion ? false : { opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5, duration: 0.7 }}
      >
        WE
      </motion.span>
    </motion.div>
  );
}
