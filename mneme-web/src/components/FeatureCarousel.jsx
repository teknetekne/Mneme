import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronLeft, ChevronRight } from "lucide-react";

const features = [
    {
        title: "Natural Language",
        desc: "Simply type what's on your mind. Apple Intelligence processes your natural language to create structured data instantly.",
        img: "/assets/notepad.png",
    },
    {
        title: "Smart Variables",
        desc: "Track expenses, meals, or any custom variable. Mneme adapts to your lifestyle.",
        img: "/assets/variables.png",
    },
    {
        title: "Synchronized Reminders",
        desc: "Seamless integration with Apple Reminders. Your tasks stay in sync across all your devices.",
        img: "/assets/reminder.png",
    },
    {
        title: "Unified Calendar",
        desc: "Full two-way sync with Apple Calendar. Manage your schedule in a unified, intelligent interface.",
        img: "/assets/calendar.png",
    },
    {
        title: "Event Management",
        desc: "Deep control over your events. Add details, location, and notes with ease.",
        img: "/assets/eventdetails.png",
    },

    {
        title: "Detailed Graphs",
        desc: "Visualize your progress. Interactive graphs help you spot trends and improvements.",
        img: "/assets/graphs.png",
    },
    {
        title: "AI Analysis",
        desc: "On-device AI finds interesting correlations between your habits, mood, and health.",
        img: "/assets/analysis.png",
    },
];

export default function FeatureCarousel() {
    const [index, setIndex] = useState(0);
    const [direction, setDirection] = useState(0);

    const nextSlide = () => {
        setDirection(1);
        setIndex((prev) => (prev + 1) % features.length);
    };

    const prevSlide = () => {
        setDirection(-1);
        setIndex((prev) => (prev - 1 + features.length) % features.length);
    };

    const variants = {
        enter: (direction) => ({
            y: direction > 0 ? 20 : -20,
            opacity: 0,
        }),
        center: {
            zIndex: 1,
            y: 0,
            opacity: 1,
        },
        exit: (direction) => ({
            zIndex: 0,
            y: direction < 0 ? 20 : -20,
            opacity: 0,
        }),
    };

    const imgVariants = {
        enter: (direction) => ({
            x: direction > 0 ? 100 : -100,
            opacity: 0,
            scale: 0.95
        }),
        center: {
            x: 0,
            opacity: 1,
            scale: 1
        },
        exit: (direction) => ({
            x: direction < 0 ? 100 : -100,
            opacity: 0,
            scale: 0.95
        })
    }

    return (
        <section className="py-24 bg-black overflow-hidden">
            <div className="max-w-[1080px] mx-auto px-6 h-[600px] flex flex-col md:flex-row items-center gap-12">

                {/* Left: Image Area */}
                <div className="flex-1 w-full h-[400px] md:h-full relative flex items-center justify-center">
                    <AnimatePresence initial={false} custom={direction} mode="wait">
                        <motion.div
                            key={index}
                            custom={direction}
                            variants={imgVariants}
                            initial="enter"
                            animate="center"
                            exit="exit"
                            transition={{ duration: 0.4, ease: "circOut" }}
                            className="absolute w-full max-w-[320px] aspect-[9/19.5]"
                        >
                            <img
                                src={features[index].img}
                                alt={features[index].title}
                                className="w-full h-full object-contain drop-shadow-2xl"
                            />
                        </motion.div>
                    </AnimatePresence>
                </div>

                {/* Right: Text Content */}
                <div className="flex-1 h-full text-left flex flex-col justify-between z-10 py-12 md:py-20">
                    <div className="flex-1 flex items-center w-full">
                        <div className="h-[200px] relative w-full">
                            <AnimatePresence initial={false} custom={direction} mode="wait">
                                <motion.div
                                    key={index}
                                    custom={direction}
                                    variants={variants}
                                    initial="enter"
                                    animate="center"
                                    exit="exit"
                                    transition={{ duration: 0.3 }}
                                    className="absolute top-0 left-0 w-full"
                                >
                                    <h2 className="text-4xl md:text-6xl font-display font-bold mb-6 leading-tight">
                                        {features[index].title}
                                    </h2>
                                    <p className="text-xl text-gray-400 leading-relaxed max-w-md">
                                        {features[index].desc}
                                    </p>
                                </motion.div>
                            </AnimatePresence>
                        </div>
                    </div>

                    {/* Controls */}
                    <div className="flex gap-4">
                        <button
                            onClick={prevSlide}
                            className="p-4 rounded-full border border-white/10 hover:bg-white/10 hover:border-white/30 transition-all active:scale-95"
                        >
                            <ChevronLeft size={24} />
                        </button>
                        <button
                            onClick={nextSlide}
                            className="p-4 rounded-full border border-white/10 hover:bg-white/10 hover:border-white/30 transition-all active:scale-95"
                        >
                            <ChevronRight size={24} />
                        </button>
                    </div>
                </div>

            </div>
        </section>
    );
}
