// TODO typesafe the form data
/* eslint-disable @typescript-eslint/no-explicit-any,@typescript-eslint/no-unused-vars */
'use client';

import {Document, Page, pdfjs} from 'react-pdf';
import React, {ChangeEvent, useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {Activity, ChevronLeft, ChevronRight, FileText, Loader2, Plus, Trash2, User, Database} from 'lucide-react';
import {Button} from "@/components/ui/button";
import {Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger,} from "@/components/ui/dialog";
import useSWR from "swr";
import {HealthData, HealthDataCreateResponse, HealthDataListResponse} from "@/app/api/health-data/route";
import DynamicForm from '../form/dynamic-form';
import JSONEditor from '../form/json-editor';
import { createId } from "@paralleldrive/cuid2";
import {cn} from "@/lib/utils";
import Image from "next/image";
import {FaChevronLeft, FaChevronRight} from 'react-icons/fa';
import testItems from '@/lib/health-data/parser/test-items.json'
import TextInput from "@/components/form/text-input";
import dynamic from "next/dynamic";
import {HealthDataParserVisionListResponse} from "@/app/api/health-data-parser/visions/route";
import {HealthDataGetResponse} from "@/app/api/health-data/[id]/route";
import {HealthDataParserDocumentListResponse} from "@/app/api/health-data-parser/documents/route";
import {HealthDataParserVisionModelListResponse} from "@/app/api/health-data-parser/visions/[id]/models/route";
import {HealthDataParserDocumentModelListResponse} from "@/app/api/health-data-parser/documents/[id]/models/route";
import {useTranslations} from "next-intl";
import {countries} from "@/lib/countries";
import {VISION_MODEL_PREFERENCES, getFirstAvailableModel} from "@/config/model-preferences";

const Select = dynamic(() => import('react-select'), {ssr: false});

// Configure PDF.js worker
if (typeof window !== 'undefined') {
    pdfjs.GlobalWorkerOptions.workerSrc = `//unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;
}

interface BoundingBox {
    vertices: { x: number, y: number }[]
}

interface Word {
    boundingBox: BoundingBox,
    confidence: number,
    id: number,
    text: string,
}

interface SymptomsData {
    date: string;
    description: string;
}

interface Field {
    key: string;
    label?: string;
    type: string;
    fields?: Field[];
    options?: { value: string; label: string }[];
    defaultValue?: string;
    placeholder?: string;
    showWhen?: (formData: Record<string, any>) => boolean;
}

interface AddSourceDialogProps {
    onFileUpload: (e: ChangeEvent<HTMLInputElement>) => void;
    onAddSymptoms: (date: string) => void;
    onImportExternalHealth: () => void;
    isSetUpVisionParser: boolean;
    isSetUpDocumentParser: boolean;
}

interface HealthDataItemProps {
    healthData: HealthData;
    isSelected: boolean;
    onClick: () => void;
    onDelete: (id: string) => void;
}

interface HealthDataPreviewProps {
    healthData: HealthData;
    formData: Record<string, any>;
    setFormData: (data: Record<string, any>) => void;
    setHealthData?: (data: HealthData) => void;
}

const HealthDataType = {
    FILE: {
        id: 'FILE',
        name: 'File'
    },
    PERSONAL_INFO: {
        id: 'PERSONAL_INFO',
        name: 'Personal Info'
    },
    SYMPTOMS: {
        id: 'SYMPTOMS',
        name: 'Symptoms'
    }
};

const personalInfoFields = (t: any, top: any): Field[] => {
    return [
        {key: 'name', label: t('name'), type: 'text'},
        {
            key: 'gender',
            label: top('gender.label'),
            type: 'select',
            options: [
                {value: 'male', label: top('gender.male')},
                {value: 'female', label: top('gender.female')}
            ]
        },
        {key: 'birthDate', label: t('birthdate'), type: 'date'},
        {
            key: 'height',
            label: t('height'),
            type: 'compound',
            fields: [
                {key: 'value', type: 'number', placeholder: t('height')},
                {
                    key: 'unit',
                    type: 'select',
                    options: [
                        {value: 'cm', label: 'cm'},
                        {value: 'ft', label: 'ft'}
                    ],
                    defaultValue: 'cm'
                }
            ]
        },
        {
            key: 'weight',
            label: t('weight'),
            type: 'compound',
            fields: [
                {key: 'value', type: 'number', placeholder: t('weight')},
                {
                    key: 'unit',
                    type: 'select',
                    options: [
                        {value: 'kg', label: 'kg'},
                        {value: 'lbs', label: 'lbs'}
                    ],
                    defaultValue: 'kg'
                }
            ]
        },
        {
            key: 'ethnicity',
            label: top('ethnicity.label'),
            type: 'select',
            options: [
                {value: 'east_asian', label: top('ethnicity.options.east_asian')},
                {value: 'southeast_asian', label: top('ethnicity.options.southeast_asian')},
                {value: 'south_asian', label: top('ethnicity.options.south_asian')},
                {value: 'european', label: top('ethnicity.options.european')},
                {value: 'middle_eastern', label: top('ethnicity.options.middle_eastern')},
                {value: 'african', label: top('ethnicity.options.african')},
                {value: 'african_american', label: top('ethnicity.options.african_american')},
                {value: 'pacific_islander', label: top('ethnicity.options.pacific_islander')},
                {value: 'native_american', label: top('ethnicity.options.native_american')},
                {value: 'hispanic', label: top('ethnicity.options.hispanic')},
                {value: 'mixed', label: top('ethnicity.options.mixed')},
                {value: 'other', label: top('ethnicity.options.other')}
            ],
        },
        {
            key: 'country',
            label: top('country.label'),
            type: 'select',
            options: countries.map(({code: value, name: label}) => ({value, label})),
        },
        {
            key: 'bloodType',
            label: t('bloodType'),
            type: 'select',
            options: [
                {value: 'A+', label: 'A+'},
                {value: 'A-', label: 'A-'},
                {value: 'B+', label: 'B+'},
                {value: 'B-', label: 'B-'},
                {value: 'O+', label: 'O+'},
                {value: 'O-', label: 'O-'},
                {value: 'AB+', label: 'AB+'},
                {value: 'AB-', label: 'AB-'}
            ]
        },
        {key: 'currentMedication', label: t('currentMedication'), type: 'textarea'},
        {key: 'allergies', label: t('allergies'), type: 'textarea'},
        {key: 'smokingHistory', label: t('smokingHistory'), type: 'select', options: [
            {value: 'never', label: 'Never Smoked'},
            {value: 'former', label: 'Former Smoker'},
            {value: 'current', label: 'Current Smoker'}
        ]},
        {key: 'alcoholHistory', label: t('alcoholHistory'), type: 'select', options: [
            {value: 'never', label: 'Never Drinks'},
            {value: 'former', label: 'Former Drinker'},
            {value: 'current', label: 'Current Drinker'}
        ]},
        {
            key: 'alcoholFrequency',
            label: t('alcoholFrequency'),
            type: 'select',
            options: [
                {value: 'rarely', label: 'Rarely (Less than 1 drink per day)'},
                {value: 'occasionally', label: 'Occasionally (1-2 drinks per day)'},
                {value: 'frequent', label: 'Frequently (3+ drinks per day)'}
            ],
            showWhen: (formData: Record<string, any>) => formData.alcoholHistory === 'current'
        },
        {key: 'familyHistory', label: t('familyHistory'), type: 'textarea'},
        {key: 'medicalHistory', label: t('medicalHistory'), type: 'textarea'},
        
        // Vital Signs Section
        {
            key: 'vitalSigns.pulse',
            label: 'Pulse (bpm)',
            type: 'compound',
            fields: [
                {key: 'value', type: 'number', placeholder: 'Pulse rate'},
                {key: 'unit', type: 'hidden', defaultValue: 'bpm'}
            ]
        },
        {
            key: 'vitalSigns.bloodPressure',
            label: 'Blood Pressure',
            type: 'compound',
            fields: [
                {key: 'value', type: 'text', placeholder: '120/80'},
                {key: 'unit', type: 'hidden', defaultValue: 'mmHg'}
            ]
        },
        {
            key: 'vitalSigns.oxygenSaturation',
            label: 'Oxygen Saturation (%)',
            type: 'compound',
            fields: [
                {key: 'value', type: 'number', placeholder: 'Oxygen level'},
                {key: 'unit', type: 'hidden', defaultValue: '%'}
            ]
        },
        {
            key: 'vitalSigns.bodyTemperature',
            label: 'Body Temperature',
            type: 'compound',
            fields: [
                {key: 'value', type: 'number', placeholder: 'Temperature'},
                {
                    key: 'unit',
                    type: 'select',
                    options: [
                        {value: '°C', label: '°C'},
                        {value: '°F', label: '°F'}
                    ],
                    defaultValue: '°C'
                }
            ]
        },

    ]
};

const symptomsFields = (t: any): Field[] => [
    {key: 'date', label: t('date'), type: 'date'},
    {key: 'endDate', label: t('endDate'), type: 'date'},
    {key: 'description', label: t('description'), type: 'textarea'}
];

const selectStyles = {
    control: (base: any, state: any) => ({
        ...base,
        backgroundColor: 'hsl(var(--background))',
        borderColor: state.isFocused ? 'hsl(var(--ring))' : 'hsl(var(--border))',
        color: 'hsl(var(--foreground))',
        boxShadow: state.isFocused ? '0 0 0 1px hsl(var(--ring))' : 'none',
        '&:hover': {
            borderColor: 'hsl(var(--border))'
        }
    }),
    menu: (base: any) => ({
        ...base,
        backgroundColor: 'hsl(var(--popover))',
        border: '1px solid hsl(var(--border))',
        boxShadow: '0 2px 4px rgba(0,0,0,0.1)',
        zIndex: 9999,
    }),
    option: (base: any, state: any) => ({
        ...base,
        backgroundColor: state.isSelected 
            ? 'hsl(var(--primary))' 
            : state.isFocused 
                ? 'hsl(var(--accent))' 
                : 'hsl(var(--popover))',
        color: state.isSelected 
            ? 'hsl(var(--primary-foreground))' 
            : state.isFocused 
                ? 'hsl(var(--accent-foreground))' 
                : 'hsl(var(--popover-foreground))',
        cursor: 'pointer',
        ':active': {
            backgroundColor: 'hsl(var(--accent))',
        },
    }),
    singleValue: (base: any) => ({
        ...base,
        color: 'hsl(var(--foreground))',
    }),
    placeholder: (base: any) => ({
        ...base,
        color: 'hsl(var(--muted-foreground))',
    }),
    input: (base: any) => ({
        ...base,
        color: 'hsl(var(--foreground))',
    }),
    indicatorSeparator: (base: any) => ({
        ...base,
        backgroundColor: 'hsl(var(--border))',
    }),
    dropdownIndicator: (base: any) => ({
        ...base,
        color: 'hsl(var(--muted-foreground))',
    }),
    clearIndicator: (base: any) => ({
        ...base,
        color: 'hsl(var(--muted-foreground))',
        '&:hover': {
            color: 'hsl(var(--foreground))',
        }
    })
};

const AddSourceDialog: React.FC<AddSourceDialogProps> = ({
                                                             isSetUpVisionParser,
                                                             isSetUpDocumentParser,
                                                             onFileUpload,
                                                             onAddSymptoms,
                                                             onImportExternalHealth
                                                         }) => {
    const t = useTranslations('SourceManagement')

    const [open, setOpen] = useState(false);
    const [showSettingsAlert, setShowSettingsAlert] = useState(false);
    const [uploadStatus, setUploadStatus] = useState<string>('');

    const handleFileUpload = async (e: ChangeEvent<HTMLInputElement>) => {
        if (!e.target.files?.length) return;

        try {
            if (!isSetUpVisionParser || !isSetUpDocumentParser) {
                setShowSettingsAlert(true);
                return;
            }

            setUploadStatus('uploading');
            onFileUpload(e);
            setOpen(false);
        } catch (error) {
            console.error('Failed to check settings:', error);
            setShowSettingsAlert(true);
        } finally {
            setUploadStatus('');
        }
    };

    const handleAddSymptoms = () => {
        const today = new Date().toISOString().split('T')[0];
        onAddSymptoms(today);
        setOpen(false);
    };

    const handleImportExternalHealth = () => {
        // TODO: Implement external health data import
        console.log('Import external health data');
    };

    return (
        <>
            <Dialog open={open} onOpenChange={setOpen}>
                <DialogTrigger asChild>
                    <Button variant="outline" className="w-full flex gap-2 items-center">
                        <Plus className="w-4 h-4"/>
                        {t('addSource')}
                    </Button>
                </DialogTrigger>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>{t('addNewSource')}</DialogTitle>
                    </DialogHeader>
                    <div className="flex flex-col gap-4 min-w-[300px]">
                        <label
                            htmlFor="file-upload"
                            className={cn(
                                "flex items-center gap-4 p-4 border rounded-lg cursor-pointer hover:bg-accent hover:text-accent-foreground transition-colors",
                                uploadStatus === 'uploading' && "opacity-50 cursor-not-allowed"
                            )}
                        >
                            {uploadStatus === 'uploading' ? (
                                <Loader2 className="h-6 w-6 text-muted-foreground animate-spin"/>
                            ) : (
                                <FileText className="w-6 h-6 text-muted-foreground"/>
                            )}
                            <div className="flex-1">
                                <h3 className="font-medium">{t('uploadFiles')}</h3>
                                <p className="text-sm text-muted-foreground">{t('uploadFilesDescription')}</p>
                            </div>
                        </label>
                        <input
                            type="file"
                            id="file-upload"
                            multiple
                            accept="image/png,image/jpeg,.pdf"
                            className="hidden"
                            onChange={handleFileUpload}
                            disabled={uploadStatus === 'uploading'}
                        />

                        <button
                            className="flex items-center gap-4 p-4 border rounded-lg cursor-pointer hover:bg-accent hover:text-accent-foreground transition-colors w-full"
                            onClick={handleAddSymptoms}
                        >
                            <Activity className="w-6 h-6 text-muted-foreground"/>
                            <div className="flex-1 text-left">
                                <h3 className="font-medium">{t('uploadSymptoms')}</h3>
                                <p className="text-sm text-muted-foreground">{t('uploadSymptomsDescription')}</p>
                            </div>
                        </button>

                        <button
                            className="flex items-center gap-4 p-4 border rounded-lg cursor-pointer hover:bg-accent hover:text-accent-foreground transition-colors w-full"
                            onClick={onImportExternalHealth}
                        >
                            <Database className="w-6 h-6 text-muted-foreground"/>
                            <div className="flex-1 text-left">
                                <h3 className="font-medium">{t('importExternalHealth')}</h3>
                                <p className="text-sm text-muted-foreground">{t('importExternalHealthDescription')}</p>
                            </div>
                        </button>
                    </div>
                </DialogContent>
            </Dialog>

            {showSettingsAlert && (
                <Dialog open={showSettingsAlert} onOpenChange={setShowSettingsAlert}>
                    <DialogContent>
                        <DialogHeader>
                            <DialogTitle>Settings Required</DialogTitle>
                        </DialogHeader>
                        <div className="space-y-4">
                            <p className="text-sm">Please configure the parsing settings before uploading files. You
                                need to:</p>
                            <ul className="list-disc pl-4 text-sm space-y-2">
                                <li>Select your preferred Vision and OCR models</li>
                                <li>Enter the required API keys</li>
                            </ul>
                            <p className="text-sm">You can find these settings in the Parsing Settings panel on the
                                right.</p>
                            <div className="flex justify-end">
                                <Button onClick={() => setShowSettingsAlert(false)}>
                                    OK
                                </Button>
                            </div>
                        </div>
                    </DialogContent>
                </Dialog>
            )}
        </>
    );
};

const HealthDataItem: React.FC<HealthDataItemProps> = ({healthData, isSelected, onClick, onDelete}) => {
    const t = useTranslations('SourceManagement')
    const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
    
    console.log('[DEBUG] HealthDataItem rendered:', healthData.type, healthData.id, 'selected:', isSelected);

    const getIcon = (type: string) => {
        switch (type) {
            case HealthDataType.FILE.id:
                return <FileText className="h-5 w-5"/>;
            case HealthDataType.PERSONAL_INFO.id:
                return <User className="h-5 w-5"/>;
            case HealthDataType.SYMPTOMS.id:
                return <Activity className="h-5 w-5"/>;
            default:
                return <FileText className="h-5 w-5"/>;
        }
    };

    const getName = (type: string) => {
        if (type === HealthDataType.PERSONAL_INFO.id) {
            return t('personalInfo')
        } else if (type === HealthDataType.SYMPTOMS.id && healthData.data) {
            const data = healthData.data as unknown as SymptomsData;
            if (data.date) {
                return `${t('symptoms')} (${data.date})`;
            } else {
                return `${t('symptoms')}`;
            }
        }
        if (type === HealthDataType.FILE.id && healthData.data) {
            const data = healthData.data as any;
            return data.fileName || HealthDataType.FILE.name;
        }
        return Object.values(HealthDataType)
            .find((t) => t.id === type)?.name || '';
    };

    return (
        <div
            className={`flex items-center justify-between p-2 rounded cursor-pointer transition-all
${isSelected
                ? 'text-primary text-base font-semibold bg-primary/5'
                : 'text-sm hover:bg-accent hover:text-accent-foreground'}`}
            onClick={(e) => {
                console.log('[DEBUG] HealthDataItem clicked:', healthData.type, healthData.id);
                onClick();
            }}
        >
            <div className="flex items-center gap-2 flex-1 min-w-0">
                <div className="flex-shrink-0">
                    {getIcon(healthData.type)}
                </div>
                <span className="truncate">{getName(healthData.type)}</span>
            </div>
            <div className="flex items-center gap-1">
                {healthData.status === 'PARSING' && (
                    <Loader2 className="h-5 w-5 animate-spin"/>
                )}
                <Dialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
                    <DialogTrigger asChild>
                        <Button
                            variant="ghost"
                            onClick={(e) => {
                                e.stopPropagation();
                            }}
                        >
                            <Trash2 className="h-5 w-5"/>
                        </Button>
                    </DialogTrigger>
                    <DialogContent>
                        <DialogHeader>
                            <DialogTitle>Confirm Deletion</DialogTitle>
                        </DialogHeader>
                        <div className="space-y-4">
                            <p className="text-sm">
                                Are you sure you want to delete &ldquo;{getName(healthData.type)}&rdquo;? This action cannot be undone.
                            </p>
                            <div className="flex justify-end gap-2">
                                <Button 
                                    variant="outline" 
                                    onClick={() => setShowDeleteConfirm(false)}
                                >
                                    Cancel
                                </Button>
                                <Button 
                                    variant="destructive" 
                                    onClick={() => {
                                        onDelete(healthData.id);
                                        setShowDeleteConfirm(false);
                                    }}
                                >
                                    Delete
                                </Button>
                            </div>
                        </div>
                    </DialogContent>
                </Dialog>
            </div>
        </div>
    );
};

const HealthDataPreview = ({healthData, formData, setFormData, setHealthData}: HealthDataPreviewProps) => {
    const t = useTranslations('SourceManagement')
    const top = useTranslations('Onboarding.personalInfo');

    const [loading, setLoading] = useState<boolean>(false);
    const [numPages, setNumPages] = useState(0);
    const [page, setPage] = useState<number>(1);
    const [focusedItem, setFocusedItem] = useState<string | null>(null);
    const [inputFocusStates, setInputFocusStates] = useState<{ [key: string]: boolean }>({});
    const inputRefs = useRef<{ [key: string]: HTMLInputElement | null }>({});

    const [showAddFieldModal, setShowAddFieldModal] = useState<boolean>(false);
    const [showAddFieldName, setShowAddFieldName] = useState<{
        value: string;
        label: string;
        isDisabled?: boolean
    } | undefined>(undefined);

    const [userBloodTestResults, setUserBloodTestResults] = useState<{
        test_result: { [key: string]: { value: string, unit: string } }
    } | null>(null);

    const [userBloodTestResultsPage, setUserBloodTestResultsPage] = useState<{
        [key: string]: { page: number }
    } | null>(null);

    const {ocr, dataPerPage: sourceDataPerPage} = (healthData?.metadata || {}) as {
        ocr?: any,
        dataPerPage?: any
    };
    const [dataPerPage, setDataPerPage] = useState(sourceDataPerPage)

    const allInputsBlurred = Object.values(inputFocusStates).every((isFocused) => !isFocused);
    
    // Track the last processed healthData to prevent unnecessary updates
    const lastProcessedHealthDataRef = useRef<string>('');
    
    // Ensure formData is in sync with healthData when healthData changes
    useEffect(() => {
        if (healthData?.data && typeof healthData.data === 'object') {
            const healthDataString = JSON.stringify(healthData.data);
            
            // Only update if this is actually new healthData
            if (healthDataString !== lastProcessedHealthDataRef.current) {
                console.log('[UI] HealthData changed, updating formData to:', JSON.stringify(healthData.data, null, 2));
                setFormData({...(healthData.data as Record<string, any>)});
                lastProcessedHealthDataRef.current = healthDataString;
            }
        }
    }, [healthData?.data, healthData?.updatedAt, healthData?.id, setFormData]);
    
    // Debug logging for Personal Info form data
    useEffect(() => {
        if (healthData?.type === HealthDataType.PERSONAL_INFO.id) {
            console.log('[UI] Personal Info form data changed:', JSON.stringify(formData, null, 2));
            console.log('[UI] Current selected health data:', healthData?.id, healthData?.updatedAt);
        }
    }, [formData, healthData?.type, healthData?.id, healthData?.updatedAt]);

    const handleFocus = (name: string) => {
        setFocusedItem(name);
        setInputFocusStates((prev) => ({...prev, [name]: true}));
    };

    const handleBlur = (name: string) => {
        if (focusedItem === name) setFocusedItem(null);
        setInputFocusStates((prev) => ({...prev, [name]: false}));
    };

    const handleKeyDown = (event: React.KeyboardEvent<HTMLInputElement>, name: string) => {
        if (event.key === 'Enter') {
            const inputNames = Object.keys(inputRefs.current);
            const currentIndex = inputNames.indexOf(name);
            const nextInput = inputRefs.current[inputNames[currentIndex + 1]];
            if (nextInput) {
                nextInput.focus();
            } else {
                event.currentTarget.blur();
            }

        }
    };

    const getNearestBoundingBox = (a: BoundingBox, b: BoundingBox): number => {
        const aCenter = {
            x: a.vertices.reduce((acc, cur) => acc + cur.x, 0) / a.vertices.length,
            y: a.vertices.reduce((acc, cur) => acc + cur.y, 0) / a.vertices.length,
        }

        const bCenter = {
            x: b.vertices.reduce((acc, cur) => acc + cur.x, 0) / b.vertices.length,
            y: b.vertices.reduce((acc, cur) => acc + cur.y, 0) / b.vertices.length,
        }

        const aDistance = Math.sqrt(Math.pow(aCenter.x, 2) + Math.pow(aCenter.y, 2));
        const bDistance = Math.sqrt(Math.pow(bCenter.x, 2) + Math.pow(bCenter.y, 2));

        return aDistance - bDistance;
    }

    const getFocusedWords = useCallback((page: number, keyword: string): Word[] => {
        if (!keyword) return [];
        if (!ocr) return [];
        const ocrPageData: { words: Word[] } = ocr.pages[page - 1];
        if (!ocrPageData) return [];
        let eFields = ocrPageData.words.filter((word) => word.text === keyword)
        if (eFields.length === 0) {
            eFields = ocrPageData.words.filter((word) => word.text.includes(keyword))
        }
        return eFields.sort((a, b) => getNearestBoundingBox(a.boundingBox, b.boundingBox));
    }, [ocr]);

    const currentPageTestResults = useMemo(() => {
        if (!dataPerPage) return {}

        const {test_result} = formData as {
            test_result: { [key: string]: { value: string, unit: string } }
        }

        const entries = Object.entries(dataPerPage).filter(([, value]) => {
            if (!value) return false;
            const {page: fieldPage} = value as { page: number }
            return fieldPage === page
        }).map(([key,]) => key);

        if (!dataPerPage) return {};

        return Object.entries(dataPerPage).reduce((acc, [key, value]) => {
            const newValue = test_result[key] || {value: '', unit: ''};
            if (entries.includes(key)) {
                return {...acc, [key]: newValue}
            }
            return acc
        }, {})
    }, [page, dataPerPage, formData]);

    const sortedPageTestResults = useMemo(() => {
        return testItems
            .filter((item) => Object.entries(currentPageTestResults).some(([key, _]) => key === item.name))
            .sort((a, b) => {
                const aFocusedWords = userBloodTestResults?.test_result[a.name] ? getFocusedWords(page, userBloodTestResults?.test_result[a.name].value) : [];
                const bFocusedWords = userBloodTestResults?.test_result[b.name] ? getFocusedWords(page, userBloodTestResults?.test_result[b.name].value) : [];

                // focused words 에 좌표 정보가 없는게 있으면 가장 마지막 인덱스로 보내기
                if (aFocusedWords.length === 0) return 1;
                if (bFocusedWords.length === 0) return -1;

                return getNearestBoundingBox(aFocusedWords[0].boundingBox, bFocusedWords[0].boundingBox);
            })
    }, [getFocusedWords, page, currentPageTestResults, userBloodTestResults?.test_result])

    const getFields = (): Field[] => {
        switch (healthData.type) {
            case HealthDataType.PERSONAL_INFO.id:
                return personalInfoFields(t, top);
            case HealthDataType.SYMPTOMS.id:
                return symptomsFields(t);
            default:
                return [];
        }
    };

    const handleFormChange = useCallback((key: string, value: any) => {
        setFormData((prevFormData: Record<string, any>) => {
            // Handle nested keys like 'clinical_data.document_type' or 'test_result.pulse.value'
            if (key.includes('.')) {
                const keys = key.split('.');
                const newData = {...prevFormData};
                let current = newData;
                
                // Navigate to the parent object, creating nested objects as needed
                for (let i = 0; i < keys.length - 1; i++) {
                    if (!current[keys[i]]) {
                        current[keys[i]] = {};
                    }
                    current = current[keys[i]];
                }
                
                // Set the final value
                current[keys[keys.length - 1]] = value;
                return newData;
            } else {
                // Handle simple keys
                return {...prevFormData, [key]: value};
            }
        });
    }, [setFormData]);

    const handleJSONSave = (newData: Record<string, any>) => {
        setFormData(newData);
    };

    const onDocumentLoadSuccess = async ({numPages}: pdfjs.PDFDocumentProxy) => {
        setLoading(true);
        setNumPages(numPages);
        setUserBloodTestResults(JSON.parse(JSON.stringify(healthData.data)));
        setUserBloodTestResultsPage(dataPerPage);
        setTimeout(() => {
            setLoading(false);
        }, 300);
    }

    useEffect(() => {
        let focusedWords: Word[];

        if (userBloodTestResultsPage && focusedItem !== null) {
            const resultPage = userBloodTestResultsPage[focusedItem];
            const result = userBloodTestResults?.test_result[focusedItem];
            if (!resultPage || !result) return;
            const {page} = resultPage;
            focusedWords = getFocusedWords(page, result.value);
        } else {
            focusedWords = Object.entries(currentPageTestResults).map(([_, value]) => {
                return getFocusedWords(page, (value as any).value);
            }).flat();
        }

        if (focusedWords && ocr) {
            const ocrPageMetadata = ocr.metadata.pages[page - 1];

            // pdf canvas
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            if (!ctx) return;

            const element: HTMLElement | null = document.querySelector(`div[data-page-number="${page}"]`);
            if (!element) return;

            const pageElement = element.querySelector('canvas');
            if (!pageElement) return;

            canvas.width = pageElement.width;
            canvas.height = pageElement.height;
            canvas.style.position = 'absolute';
            canvas.style.top = '0';
            canvas.style.left = '0';
            canvas.style.width = pageElement.style.width;
            canvas.style.height = pageElement.style.height;

            ctx.drawImage(pageElement, 0, 0);

            ctx.strokeStyle = 'red';
            ctx.lineWidth = 2;

            const paddingX = 5;
            const paddingY = 5;

            focusedWords.forEach((word) => {
                const {vertices} = word.boundingBox;

                const originalHeight = ocrPageMetadata.height;
                const originalWidth = ocrPageMetadata.width;

                const canvasWidth = pageElement.width;
                const canvasHeight = pageElement.height;

                const scaleX = canvasWidth / originalWidth;
                const scaleY = canvasHeight / originalHeight;

                ctx.beginPath();
                ctx.moveTo(vertices[0].x * scaleX - paddingX, vertices[0].y * scaleY - paddingY);
                ctx.lineTo(vertices[1].x * scaleX + paddingX, vertices[1].y * scaleY - paddingY);
                ctx.lineTo(vertices[2].x * scaleX + paddingX, vertices[2].y * scaleY + paddingY);
                ctx.lineTo(vertices[3].x * scaleX - paddingX, vertices[3].y * scaleY + paddingY);
                ctx.closePath();
                ctx.stroke();
            });

            element.style.position = 'relative';
            element.appendChild(canvas);

            return () => {
                element.removeChild(canvas);
            };
        }

    }, [loading, focusedItem, getFocusedWords, ocr, userBloodTestResults?.test_result, allInputsBlurred, page, currentPageTestResults, userBloodTestResultsPage]);

    useEffect(() => {
        document.querySelector('#test-result')?.scrollTo(0, 0);
        document.querySelector('#pdf')?.scrollTo(0, 0);
    }, [page]);

    return (
        <>
            <div className="flex flex-col gap-4 h-full">
                <div className="h-[40%] min-h-[300px]">
                    <div className="bg-background h-full overflow-y-auto rounded-lg border">
                        {(healthData?.type === HealthDataType.PERSONAL_INFO.id || healthData?.type === HealthDataType.SYMPTOMS.id) ? (
                            <div className="p-4">
                                <DynamicForm
                                    key={`form-${healthData.id}`}
                                    fields={getFields()}
                                    data={formData}
                                    onChange={handleFormChange}
                                />
                            </div>
                        ) : healthData?.type === HealthDataType.FILE.id ? (
                            (() => {
                                console.log('[UI] FILE selected - data:', healthData?.data, 'fileType:', healthData?.fileType);
                                return healthData?.fileType?.includes('image') && healthData?.filePath;
                            })() ? (
                                <div className="p-4">
                                    <Image
                                        src={healthData.filePath!}
                                        alt="Preview"
                                        className="w-full h-auto"
                                        width={800}
                                        height={600}
                                        unoptimized
                                        style={{objectFit: 'contain'}}
                                    />
                                </div>
                            ) : (
                                <div className="bg-background p-4 rounded-lg relative flex flex-row h-full">
                                    {healthData?.fileType?.includes('pdf') ? (
                                        <div id="pdf" className="w-[60%] overflow-y-auto h-full">
                                            <Document file={healthData.filePath}
                                                      className="w-full"
                                                      onLoadSuccess={onDocumentLoadSuccess}>
                                                {Array.from(new Array(numPages), (_, index) => {
                                                    return (
                                                        <Page
                                                            className={cn(
                                                                'w-full',
                                                                {hidden: index + 1 !== page}
                                                            )}
                                                            key={`page_${index + 1}`}
                                                            pageNumber={index + 1}
                                                            renderAnnotationLayer={false}
                                                            renderTextLayer={false}
                                                        />
                                                    );
                                                })}
                                            </Document>
                                            <div
                                                className="relative w-fit bottom-4 left-1/2 transform -translate-x-1/2 flex items-center space-x-4 bg-background p-2 rounded shadow">
                                                <button
                                                    className="px-4 py-2 bg-secondary text-secondary-foreground rounded hover:bg-secondary/80 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                                                    onClick={() => setPage((prev) => Math.max(prev - 1, 1))}
                                                    disabled={page <= 1}
                                                >
                                                    <FaChevronLeft/>
                                                </button>
                                                <span className="text-foreground">{page} / {numPages}</span>
                                                <button
                                                    className="px-4 py-2 bg-secondary text-secondary-foreground rounded hover:bg-secondary/80 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                                                    onClick={() => setPage((prev) => Math.min(prev + 1, numPages))}
                                                    disabled={page >= numPages}
                                                >
                                                    <FaChevronRight/>
                                                </button>
                                            </div>
                                        </div>
                                    ) : (
                                        <div className="w-[60%] overflow-y-auto h-full flex items-center justify-center">
                                            <div className="text-center text-muted-foreground">
                                                <FileText className="h-16 w-16 mx-auto mb-4" />
                                                <p className="text-sm">Document preview not available</p>
                                                <p className="text-xs">File type: {healthData?.fileType || 'Unknown'}</p>
                                            </div>
                                        </div>
                                    )}
                                    {userBloodTestResults?.test_result ? <div
                                        id="test-result"
                                        className="w-[40%] overflow-y-auto p-4">
                                        {sortedPageTestResults.map((item) =>
                                            <TextInput
                                                key={item.name}
                                                name={item.name.replace(/(^\w|_\w)/g, (match) => match.replace('_', '').toUpperCase())}
                                                label={item.description}
                                                value={
                                                    userBloodTestResults && userBloodTestResults.test_result ? userBloodTestResults.test_result[item.name]?.value : ''
                                                }
                                                onChange={(v) => {
                                                    setUserBloodTestResults((prev) => {
                                                        return {
                                                            ...prev,
                                                            test_result: {
                                                                ...prev?.test_result,
                                                                [item.name]: {
                                                                    ...prev?.test_result[item.name],
                                                                    value: v.target.value,
                                                                }
                                                            }
                                                        } as any;
                                                    });
                                                    setFormData({
                                                        ...formData,
                                                        test_result: {
                                                            ...formData?.test_result,
                                                            [item.name]: {
                                                                ...formData?.test_result[item.name],
                                                                value: v.target.value,
                                                            }
                                                        }
                                                    })
                                                }}
                                                onDelete={() => {
                                                    setUserBloodTestResults((prev) => {
                                                        const {test_result} = prev ?? {test_result: {}};
                                                        delete test_result[item.name];
                                                        return {test_result};
                                                    });

                                                    // Delete From Metadata
                                                    setDataPerPage((prev: any) => {
                                                        delete prev[item.name]
                                                        return {...prev}
                                                    })

                                                    // Delete From FormData
                                                    delete formData.test_result[item.name]
                                                    setFormData(formData)

                                                    // Update Health Data
                                                    if (setHealthData) {
                                                        const metadata: any = healthData.metadata || {}
                                                        delete dataPerPage[item.name]
                                                        setHealthData({
                                                            ...healthData,
                                                            metadata: {...metadata, dataPerPage}
                                                        })
                                                    }
                                                }}
                                                onBlur={(v) => handleBlur(item.name)}
                                                onFocus={(v) => handleFocus(item.name)}
                                                onKeyDown={(e) => handleKeyDown(e, item.name)}
                                                ref={(el) => {
                                                    inputRefs.current[item.name] = el;
                                                }}
                                            />)}

                                        {healthData &&
                                            <div className="mt-4 w-full">
                                                <button
                                                    className="w-full py-2 bg-primary text-primary-foreground rounded"
                                                    onClick={() => {
                                                        setShowAddFieldName(undefined);
                                                        setShowAddFieldModal(true);
                                                    }}
                                                >
                                                    Add
                                                </button>
                                            </div>
                                        }
                                    </div> : 
                                    <div className="w-[40%] overflow-y-auto p-4">
                                        <h3 className="text-sm font-medium mb-4">Extracted Data</h3>
                                        <div className="mb-2 text-xs text-green-600 bg-green-50 p-2 rounded">
                                            Clinical document detected - showing clinical form
                                        </div>
                                        <div className="space-y-4">
                                            <div className="mb-2 text-xs text-muted-foreground bg-yellow-100 p-2 rounded">
                                                <div>Debug: {formData.clinical_data ? 'Clinical data found' : 'No clinical data'}</div>
                                                <div>Form data keys: {Object.keys(formData).join(', ')}</div>
                                                <div>Has test_result: {formData.test_result ? 'Yes' : 'No'}</div>
                                                <div>Test result keys: {formData.test_result ? Object.keys(formData.test_result).join(', ') : 'None'}</div>
                                            </div>
                                            
                                            {(() => {
                                                const hasVitalSigns = formData.test_result && Object.keys(formData.test_result).length > 0;
                                                const isClinicalDoc = formData.fileName?.toLowerCase().includes('clinical') || 
                                                                     formData.fileName?.toLowerCase().includes('ambulatory');
                                                console.log('[UI] Form render check:', {hasVitalSigns, isClinicalDoc, formData});
                                                return hasVitalSigns || isClinicalDoc;
                                            })() ? (
                                                // Show combined form for medical documents with extracted data
                                                <div className="space-y-6">
                                                    {/* Vital Signs / Test Results Section */}
                                                    {formData.test_result && Object.keys(formData.test_result).length > 0 && (
                                                        <div>
                                                            <h4 className="text-sm font-semibold mb-2 text-blue-600">Extracted Vital Signs & Test Results</h4>
                                                            <DynamicForm
                                                                key={`test-results-${healthData.id}`}
                                                                fields={Object.keys(formData.test_result).map(key => ({
                                                                    key: `test_result.${key}.value`,
                                                                    label: key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()) + 
                                                                           (formData.test_result[key]?.unit ? ` (${formData.test_result[key].unit})` : ''),
                                                                    type: 'text'
                                                                }))}
                                                                data={formData}
                                                                onChange={handleFormChange}
                                                            />
                                                        </div>
                                                    )}
                                                    
                                                    {/* Clinical Data Section */}
                                                    <div>
                                                        <h4 className="text-sm font-semibold mb-2 text-green-600">Clinical Information</h4>
                                                        <DynamicForm
                                                            key={`clinical-form-${healthData.id}`}
                                                            fields={[
                                                                {key: 'fileName', label: 'File Name', type: 'text'},
                                                                {key: 'clinical_data.document_type', label: 'Document Type', type: 'text'},
                                                                {key: 'clinical_data.patient_name', label: 'Patient Name', type: 'text'},
                                                                {key: 'clinical_data.provider_name', label: 'Provider', type: 'text'},
                                                                {key: 'clinical_data.institution', label: 'Institution', type: 'text'},
                                                                {key: 'clinical_data.visit_date', label: 'Visit Date', type: 'date'},
                                                                {key: 'clinical_data.chief_complaint', label: 'Chief Complaint', type: 'textarea'},
                                                                {key: 'clinical_data.assessment', label: 'Assessment', type: 'textarea'},
                                                                {key: 'clinical_data.diagnosis', label: 'Diagnosis', type: 'textarea'},
                                                                {key: 'clinical_data.treatment_plan', label: 'Treatment Plan', type: 'textarea'},
                                                                {key: 'clinical_data.medications', label: 'Medications', type: 'textarea'},
                                                                {key: 'clinical_data.follow_up', label: 'Follow-up', type: 'textarea'},
                                                                {key: 'clinical_data.physical_examination', label: 'Physical Exam', type: 'textarea'},
                                                                {key: 'clinical_data.imaging_findings', label: 'Imaging Findings', type: 'textarea'},
                                                                {key: 'clinical_data.clinical_notes', label: 'Clinical Notes', type: 'textarea'},
                                                                {key: 'clinical_data.summary', label: 'Summary', type: 'textarea'}
                                                            ]}
                                                            data={formData}
                                                            onChange={handleFormChange}
                                                        />
                                                    </div>
                                                </div>
                                            ) : (
                                                // Standard form for other documents
                                                <DynamicForm
                                                    key={`file-form-${healthData.id}`}
                                                    fields={[
                                                        {key: 'fileName', label: 'File Name', type: 'text'},
                                                        {key: 'documentType', label: 'Document Type', type: 'text'},
                                                        {key: 'summary', label: 'Summary', type: 'textarea'},
                                                        {key: 'extractedText', label: 'Extracted Text', type: 'textarea'},
                                                        {key: 'keyFindings', label: 'Key Findings', type: 'textarea'},
                                                        // Show any other extracted fields dynamically
                                                        ...Object.keys(formData).filter(key => 
                                                            !['fileName', 'documentType', 'summary', 'extractedText', 'keyFindings', 'test_result', 'clinical_data'].includes(key) &&
                                                            formData[key] !== null && formData[key] !== undefined
                                                        ).map(key => ({
                                                            key,
                                                            label: key.replace(/([A-Z])/g, ' $1').replace(/^./, str => str.toUpperCase()),
                                                            type: typeof formData[key] === 'string' && formData[key].length > 50 ? 'textarea' : 'text'
                                                        }))
                                                    ]}
                                                    data={formData}
                                                    onChange={handleFormChange}
                                                />
                                            )}
                                        </div>
                                    </div>}
                                </div>
                            )
                        ) : null}
                    </div>
                </div>

                <div className="flex-1">
                    <div className="bg-background rounded-lg border h-full flex flex-col gap-4">
                        <div className="flex-1 min-h-0 p-4">
                            <JSONEditor
                                data={formData}
                                onSave={handleJSONSave}
                                isEditable={healthData?.type === HealthDataType.FILE.id && healthData?.status === 'COMPLETED'}
                            />
                        </div>
                        {healthData?.type === HealthDataType.FILE.id && formData.parsingLogs && (
                            <div className="border-t">
                                <div className="p-4">
                                    <h3 className="text-sm font-medium mb-2">Processing Log</h3>
                                    <div
                                        className="h-[160px] bg-background p-3 rounded-lg text-sm font-mono overflow-y-auto">
                                        {(formData.parsingLogs as string[]).map((log, index) => (
                                            <div key={index} className="mb-1">
                                                {log}
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            </div>
                        )}
                    </div>
                </div>
            </div>
            {showAddFieldModal && <div
                className="fixed top-0 left-0 w-screen h-screen bg-black bg-opacity-50 flex justify-center items-center">
                {/* Input modal for adding, searchable dropdown to select a field, with confirm and cancel buttons */}
                <div className="bg-background p-4 rounded-lg flex flex-col w-[50vw]">
                    <p className="mb-4 font-bold">
                        Please select a field to add
                    </p>
                    <Select
                        className="basic-single text-sm"
                        classNamePrefix="select"
                        isDisabled={false}
                        isLoading={false}
                        isClearable={true}
                        isRtl={false}
                        isSearchable={true}
                        name="field"
                        placeholder="Search for a field..."
                        options={testItems.map((bloodTestItem) => (
                            {
                                value: bloodTestItem.name,
                                label: `${bloodTestItem.name} (${bloodTestItem.description})`,
                                isDisabled: Object.entries(userBloodTestResults?.test_result ?? {}).filter(([_, value]) => value).map(([key, _]) => key).includes(bloodTestItem.name),
                            }
                        ))}
                        value={showAddFieldName}
                        onChange={(selectedOption) => {
                            if (selectedOption) {
                                setShowAddFieldName(selectedOption as {
                                    value: string;
                                    label: string;
                                    isDisabled?: boolean
                                });
                            } else {
                                setShowAddFieldName(undefined);
                            }
                        }}
                        styles={selectStyles}
                    />
                    <div className="flex flex-row gap-2 mt-4">
                        <p className={
                            cn(
                                'bg-primary text-primary-foreground py-2 px-4 rounded',
                                'hover:bg-primary/90',
                                'focus:outline-none focus:ring-2 focus:ring-primary focus:ring-opacity-50',
                            )
                        }
                           onClick={() => {
                               if (showAddFieldName) {
                                   const value = showAddFieldName.value

                                   setUserBloodTestResults((prev) => {
                                       return {
                                           test_result: {
                                               ...prev?.test_result,
                                               [value]: {
                                                   value: '',
                                                   unit: '',
                                               }
                                           }
                                       } as any;
                                   });

                                   setDataPerPage({
                                       ...dataPerPage,
                                       [value]: {page: page}
                                   })
                                   setUserBloodTestResultsPage({
                                       ...userBloodTestResultsPage,
                                       [value]: {page: page}
                                   })

                                   setFormData(
                                       {
                                           ...formData,
                                           test_result: {
                                               ...formData?.test_result,
                                               [value]: {
                                                   value: '',
                                                   unit: '',
                                               }
                                           }
                                       }
                                   )

                                   // Update Health Data
                                   if (setHealthData) {
                                       const metadata: any = healthData.metadata || {}
                                       setHealthData({
                                           ...healthData,
                                           metadata: {
                                               ...metadata, dataPerPage: {
                                                   ...dataPerPage,
                                                   [value]: {page: page}
                                               }
                                           }
                                       })
                                   }

                               }
                               setShowAddFieldModal(false);
                           }}
                        >Add
                        </p>
                        <p className={
                            cn(
                                'bg-secondary text-secondary-foreground py-2 px-4 rounded cursor-pointer',
                                'hover:bg-secondary/80',
                                'focus:outline-none focus:ring-2 focus:ring-ring focus:ring-opacity-50',
                                'transition-colors'
                            )
                        }
                           onClick={() => setShowAddFieldModal(false)}
                        >Cancel</p>
                    </div>
                </div>
            </div>
            }
        </>
    );
};

export default function SourceAddScreen() {
    console.log('[DEBUG] SourceAddScreen component loaded');
    const t = useTranslations('SourceManagement')

    const [selectedId, setSelectedId] = useState<string | null>(null);
    const [formData, setFormData] = useState<Record<string, any>>({});
    const [isOpen, setIsOpen] = useState(true);

    // Vision Parser
    const [visionParser, setVisionParser] = useState<{ value: string; label: string }>()
    const [visionParserModel, setVisionParserModel] = useState<{ value: string; label: string }>()
    const [visionParserApiKey, setVisionParserApiKey] = useState<string>('')
    const [visionParserApiUrl, setVisionParserApiUrl] = useState<string>('')

    // Document Parser
    const [documentParser, setDocumentParser] = useState<{ value: string; label: string }>()
    const [documentParserModel, setDocumentParserModel] = useState<{ value: string; label: string }>()
    const [documentParserApiKey, setDocumentParserApiKey] = useState<string>('')

    const {data: healthDataList, mutate} = useSWR<HealthDataListResponse>(
        '/api/health-data',
        (url: string) => fetch(url).then((res) => res.json()),
    );
    
    console.log('[DEBUG] healthDataList:', healthDataList?.healthDataList?.length, 'items');

    const {data: visionDataList} = useSWR<HealthDataParserVisionListResponse>(
        '/api/health-data-parser/visions',
        (url: string) => fetch(url).then((res) => res.json()),
    )

    const {data: visionModelDataList} = useSWR<HealthDataParserVisionModelListResponse>(
        `/api/health-data-parser/visions/${visionParser?.value}/models?apiUrl=${visionParserApiUrl}`,
        (url: string) => fetch(url).then((res) => res.json()),
    )

    const {data: documentDataList} = useSWR<HealthDataParserDocumentListResponse>(
        '/api/health-data-parser/documents',
        (url: string) => fetch(url).then((res) => res.json()),
    )

    const {data: documentModelDataList} = useSWR<HealthDataParserDocumentModelListResponse>(
        `/api/health-data-parser/documents/${documentParser?.value}/models`,
        (url: string) => fetch(url).then((res) => res.json()),
    )

    const handleFileUpload = async (e: ChangeEvent<HTMLInputElement>) => {
        if (!e.target.files?.length) return;

        try {
            const files = Array.from(e.target.files);

            for (const file of files) {
                const id = createId();
                const formData = new FormData();
                formData.append('file', file);
                formData.append('id', id);

                // Vision Parser
                if (visionParser?.value) formData.append('visionParser', visionParser.value);
                if (visionParserModel?.value) formData.append('visionParserModel', visionParserModel.value);
                if (visionParserApiKey) formData.append('visionParserApiKey', visionParserApiKey);
                if (visionParserApiUrlRequired) formData.append('visionParserApiUrl', visionParserApiUrl);

                // Document Parser
                if (documentParser?.value) formData.append('documentParser', documentParser.value);
                if (documentParserModel?.value) formData.append('documentParserModel', documentParserModel.value);
                if (documentParserApiKey) formData.append('documentParserApiKey', documentParserApiKey);

                // Add temporary entries to the list first
                await mutate({
                    healthDataList: [
                        ...healthDataList?.healthDataList || [],
                        {
                            id: id,
                            type: HealthDataType.FILE.id,
                            data: {fileName: file.name} as Record<string, any>,
                            metadata: {} as Record<string, any>,
                            status: 'PARSING',
                            filePath: null,
                            fileType: file.type,
                            createdAt: new Date(),
                            updatedAt: new Date()
                        }
                    ]
                }, {revalidate: false});

                // Request
                const response = await fetch('/api/health-data', {method: 'POST', body: formData});
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Failed to upload file:', {
                        fileName: file.name,
                        status: response.status,
                        error: errorText
                    });
                    continue;
                }

                const data: HealthDataCreateResponse = await response.json();
                console.log('File upload successful:', {fileName: file.name, response: data});

                // Start polling for parsing status
                if (data.id) {
                    let attempts = 0;
                    const maxAttempts = 30; // 30 seconds timeout
                    const pollInterval = setInterval(async () => {
                        try {
                            const statusResponse = await fetch(`/api/health-data/${data.id}`);
                            const {healthData: statusData}: HealthDataGetResponse = await statusResponse.json();
                            console.log('Parsing status check:', {
                                id: data.id,
                                status: statusData.status,
                                attempt: attempts + 1
                            });

                            if (statusData.status === 'COMPLETED' || statusData.status === 'ERROR' || attempts >= maxAttempts) {
                                clearInterval(pollInterval);
                                if (statusData.status === 'ERROR') {
                                    console.error('Parsing failed:', statusData);
                                } else if (statusData.status === 'COMPLETED') {
                                    console.log('Parsing completed successfully:', statusData);
                                }
                                
                                // Refresh the health data list to include any synced personal info updates
                                await mutate();
                                
                                // Check if user currently has Personal Info selected before changing selection
                                const currentSelectedItem = healthDataList?.healthDataList?.find(item => item.id === selectedId);
                                const wasPersonalInfoSelected = currentSelectedItem?.type === HealthDataType.PERSONAL_INFO.id;
                                
                                if (wasPersonalInfoSelected) {
                                    // If Personal Info was selected, refresh it with the latest synced data
                                    const refreshedData = await fetch('/api/health-data').then(res => res.json());
                                    const personalInfo = refreshedData.healthDataList?.find((item: any) => item.type === 'PERSONAL_INFO');
                                    if (personalInfo) {
                                        console.log('Refreshing Personal Info with synced data:', personalInfo.data);
                                        setFormData(personalInfo.data as Record<string, any>);
                                        // Keep Personal Info selected instead of switching to the new file
                                        return; // Don't change selection to the new file
                                    }
                                }
                                
                                // Only switch to the new file if Personal Info wasn't selected
                                setSelectedId(data.id);
                                setFormData(statusData.data as Record<string, any>);
                            }
                            attempts++;
                        } catch (error) {
                            console.error('Failed to check parsing status:', error);
                            clearInterval(pollInterval);
                        }
                    }, 1000); // Check every second
                }
            }
        } catch (error) {
            console.error('Failed to upload files:', error);
        }
    };

    const handleAddSymptoms = async (date: string) => {
        const now = new Date();
        const body = {
            id: createId(),
            type: HealthDataType.SYMPTOMS.id,
            data: {
                date,
                description: ''
            } as Record<string, any>,
            status: 'COMPLETED',
            filePath: null,
            fileType: null,
            createdAt: now,
            updatedAt: now
        } as HealthData;

        try {
            const response = await fetch(`/api/health-data`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(body)
            });

            if (!response.ok) {
                const errorText = await response.text();
                console.error('Server response:', errorText || 'Empty response');
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const text = await response.text();
            let newSource;
            try {
                newSource = text ? JSON.parse(text) : body;
            } catch (e) {
                console.error('Failed to parse response:', e);
                newSource = body;
            }

            setSelectedId(newSource.id);
            setFormData(newSource.data as Record<string, any>);
            await mutate({healthDataList: [...healthDataList?.healthDataList || [], newSource]});
        } catch (error) {
            console.error('Failed to add symptoms:', error);
            // Add the data anyway for better UX
            setSelectedId(body.id);
            setFormData(body.data as Record<string, any>);
            await mutate({healthDataList: [...healthDataList?.healthDataList || [], body]});
        }
    };

    const handleDeleteSource = async (id: string) => {
        try {
            const response = await fetch(`/api/health-data/${id}`, {method: 'DELETE'});
            
            if (!response.ok) {
                console.error('Failed to delete health data:', response.status);
                return;
            }

            const newSources = healthDataList?.healthDataList.filter(s => s.id !== id) || [];
            await mutate({healthDataList: newSources});

            if (selectedId === id) {
                if (newSources.length > 0) {
                    setSelectedId(newSources[0].id);
                    setFormData(newSources[0].data as Record<string, any>);
                } else {
                    setSelectedId(null);
                    setFormData({})
                }
            }
        } catch (error) {
            console.error('Error deleting health data:', error);
        }
    };

    const onChangeHealthData = async (data: HealthData) => {
        if (selectedId) {
            setSelectedId(data.id);
            setFormData(data.data as Record<string, any>);
            await fetch(`/api/health-data/${selectedId}`, {
                method: 'PATCH',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(data)
            });
            await mutate({
                healthDataList: healthDataList?.healthDataList?.map(s =>
                    s.id === selectedId
                        ? data
                        : s
                ) || []
            });
        }
    };

    const onChangeFormData = async (data: Record<string, any>) => {
        if (selectedId) {
            setFormData(data);
            
            try {
                const response = await fetch(`/api/health-data/${selectedId}`, {
                    method: 'PATCH',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({data: data})
                });
                
                if (!response.ok) {
                    if (response.status === 404) {
                        // Record was deleted, clear selection
                        console.warn('Attempted to update deleted record, clearing selection');
                        setSelectedId(null);
                        setFormData({});
                        await mutate();
                        return;
                    }
                    throw new Error(`HTTP ${response.status}`);
                }
                
                await mutate({
                    healthDataList: healthDataList?.healthDataList?.map(s =>
                        s.id === selectedId
                            ? {...s, data: data}
                            : s
                    ) || []
                });
            } catch (error) {
                console.error('Failed to update health data:', error);
                // Optionally show user feedback here
            }
        }
    };

    const visionParserApiKeyRequired: boolean = useMemo(() => {
        return visionDataList?.visions?.find(v => v.name === visionParser?.value)?.apiKeyRequired || false;
    }, [visionDataList, visionParser]);

    const documentParserApiKeyRequired: boolean = useMemo(() => {
        return documentDataList?.documents?.find(d => d.name === documentParser?.value)?.apiKeyRequired || false;
    }, [documentDataList, documentParser]);

    const visionParserApiUrlRequired: boolean = useMemo(() => {
        return visionDataList?.visions?.find(v => v.name === visionParser?.value)?.apiUrlRequired || false;
    }, [visionDataList, visionParser]);

    useEffect(() => {
        if (visionDataList?.visions && visionParser === undefined) {
            const {name} = visionDataList.visions[0];
            setVisionParser({value: name, label: name})
            setVisionParserModel(undefined)
            setVisionParserApiUrl('')
        }
    }, [visionDataList, visionParser]);

    useEffect(() => {
        if (visionModelDataList?.models && visionModelDataList.models.length > 0 && !visionParserModel) {
            const initializeModel = async () => {
                const preferredModel = await getFirstAvailableModel(VISION_MODEL_PREFERENCES);
                if (preferredModel && visionModelDataList?.models) {
                    const model = visionModelDataList.models.find((m) => m.id === preferredModel.id);
                    if (model) {
                        setVisionParserModel({ value: model.id, label: model.name });
                        return;
                    }
                }
                // Fallback to first available model
                if (visionModelDataList?.models?.[0]) {
                    setVisionParserModel({
                        value: visionModelDataList.models[0].id,
                        label: visionModelDataList.models[0].name
                    });
                }
            };
            initializeModel();
        }
    }, [visionModelDataList, visionParserModel]);

    useEffect(() => {
        if (documentDataList?.documents && documentParser === undefined) {
            const {name} = documentDataList.documents[0];
            setDocumentParser({value: name, label: name})
            setDocumentParserModel(undefined)
        }
    }, [documentDataList, documentParser]);

    useEffect(() => {
        if (documentModelDataList?.models && documentModelDataList.models.length > 0 && !documentParserModel) {
            const initializeModel = async () => {
                const preferredModel = await getFirstAvailableModel(VISION_MODEL_PREFERENCES);
                if (preferredModel && documentModelDataList?.models) {
                    const model = documentModelDataList.models.find((m) => m.id === preferredModel.id);
                    if (model) {
                        setDocumentParserModel({ value: model.id, label: model.name });
                        return;
                    }
                }
                // Fallback to first available model
                if (documentModelDataList?.models?.[0]) {
                    setDocumentParserModel({
                        value: documentModelDataList.models[0].id,
                        label: documentModelDataList.models[0].name
                    });
                }
            };
            initializeModel();
        }
    }, [documentModelDataList, documentParserModel]);

    const handleImportExternalHealth = () => {
        // TODO: Implement external health data import
        console.log('Import external health data');
    };

    return (
        <div className="flex flex-col h-screen">
            <div className="h-14 border-b px-4 flex items-center justify-between">
                <h1 className="text-base font-semibold">{t('title')}</h1>
            </div>
            <div className="flex flex-1 overflow-hidden">
                <div className="w-80 border-r flex flex-col">
                    <div className="p-4 flex flex-col gap-4">
                        <AddSourceDialog
                            isSetUpVisionParser={visionParser !== undefined && visionParserModel !== undefined && (!visionParserApiKeyRequired || visionParserApiKey.length > 0)}
                            isSetUpDocumentParser={documentParser !== undefined && documentParserModel !== undefined && (!documentParserApiKeyRequired || documentParserApiKey.length > 0)}
                            onFileUpload={handleFileUpload}
                            onAddSymptoms={handleAddSymptoms}
                            onImportExternalHealth={handleImportExternalHealth}/>
                        <div className="flex-1 overflow-y-auto">
                            {healthDataList?.healthDataList?.map((item) => (
                                <HealthDataItem
                                    key={item.id}
                                    healthData={item}
                                    isSelected={selectedId === item.id}
                                    onClick={() => {
                                        console.log('[UI] Item clicked:', item.type, item.id);
                                        if (item.status === 'PARSING') return;
                                        
                                        setSelectedId(item.id);
                                        
                                        // If selecting Personal Info, always fetch the latest data
                                        if (item.type === HealthDataType.PERSONAL_INFO.id) {
                                            console.log('[UI] Personal Info clicked, fetching latest data...');
                                            
                                            // Use async operation but don't block the UI
                                            fetch('/api/health-data')
                                                .then(response => response.json())
                                                .then(refreshedData => {
                                                    console.log('[UI] All health data received:', refreshedData);
                                                    const latestPersonalInfo = refreshedData.healthDataList?.find((healthItem: any) => healthItem.type === 'PERSONAL_INFO');
                                                    if (latestPersonalInfo) {
                                                        console.log('[UI] Found latest Personal Info:', latestPersonalInfo);
                                                        console.log('[UI] Personal Info data structure:', JSON.stringify(latestPersonalInfo.data, null, 2));
                                                        console.log('[UI] About to call setFormData with:', latestPersonalInfo.data);
                                                        // Force a new object reference to trigger re-render
                                                        setFormData({...(latestPersonalInfo.data as Record<string, any>)});
                                                        console.log('[UI] setFormData called successfully');
                                                        
                                                        // Also update the healthDataList cache to keep it in sync
                                                        mutate();
                                                    } else {
                                                        console.log('[UI] No Personal Info found, using item data:', item.data);
                                                        setFormData({...(item.data as Record<string, any>)});
                                                    }
                                                })
                                                .catch(error => {
                                                    console.error('[UI] Failed to fetch latest Personal Info:', error);
                                                    setFormData({...(item.data as Record<string, any>)});
                                                });
                                        } else {
                                            console.log('[UI] Non-Personal Info selected, using item data');
                                            setFormData({...(item.data as Record<string, any>)});
                                        }
                                    }}
                                    onDelete={handleDeleteSource}
                                />
                            ))}
                        </div>
                    </div>
                </div>

                <div className="flex-1 p-4 overflow-y-auto">
                    {selectedId && healthDataList?.healthDataList && (
                        <HealthDataPreview
                            key={selectedId}
                            healthData={healthDataList.healthDataList.find(s => s.id === selectedId) as HealthData}
                            formData={formData}
                            setFormData={onChangeFormData}
                            setHealthData={onChangeHealthData}
                        />
                    )}
                </div>

                <div className={cn(
                    "border-l transition-all duration-300 flex flex-col",
                    isOpen ? "w-96" : "w-12"
                )}>
                    {isOpen ? (
                        <>
                            <div className="h-12 px-4 flex items-center justify-between border-t">
                                <h2 className="text-sm font-medium">{t('parsingSettings')}</h2>
                                <Button variant="ghost" onClick={() => setIsOpen(false)}>
                                    <ChevronRight className="h-4 w-4"/>
                                </Button>
                            </div>
                            <div className="flex-1 overflow-y-auto">
                                <div className="p-4 space-y-4">
                                    <p className="text-sm text-muted-foreground">
                                        {t('parsingSettingsDescription')}
                                    </p>

                                    <div className="space-y-4">
                                        <div>
                                            <h3 className="text-sm font-medium mb-2">{t('visionModel')}</h3>
                                            <p className="text-sm text-muted-foreground mb-2">
                                                {t('visionModelDescription')}
                                            </p>
                                            <div className="space-y-2">
                                                <Select
                                                    className="basic-single text-sm"
                                                    classNamePrefix="select"
                                                    isSearchable={false}
                                                    value={visionParser}
                                                    onChange={(selected: any) => {
                                                        setVisionParser(selected)
                                                        setVisionParserModel(undefined)

                                                        // Update API Url
                                                        const parser = visionDataList?.visions?.find(v => v.name === selected.value)
                                                        if (parser?.apiUrlRequired && parser?.apiUrl) {
                                                            setVisionParserApiUrl(parser.apiUrl)
                                                        } else {
                                                            setVisionParserApiUrl('')
                                                        }
                                                    }}
                                                    options={visionDataList?.visions?.map((vision) => ({
                                                        value: vision.name,
                                                        label: vision.name
                                                    }))}
                                                    styles={selectStyles}
                                                    theme={(theme) => ({
                                                        ...theme,
                                                        colors: {
                                                            ...theme.colors,
                                                            primary: 'var(--primary)',
                                                            primary75: 'var(--primary)',
                                                            primary50: 'var(--primary)',
                                                            primary25: 'var(--primary)',
                                                            neutral0: 'var(--popover)',
                                                            neutral5: 'var(--border)',
                                                            neutral10: 'var(--border)',
                                                            neutral20: 'var(--border)',
                                                            neutral30: 'var(--border)',
                                                            neutral40: 'var(--muted-foreground)',
                                                            neutral50: 'var(--muted-foreground)',
                                                            neutral60: 'var(--foreground)',
                                                            neutral70: 'var(--foreground)',
                                                            neutral80: 'var(--foreground)',
                                                            neutral90: 'var(--foreground)',
                                                        },
                                                    })}
                                                />

                                                <Select
                                                    className="basic-single text-sm"
                                                    classNamePrefix="select"
                                                    isSearchable={false}
                                                    placeholder={t('selectModel')}
                                                    value={visionParserModel}
                                                    onChange={(selected: any) => setVisionParserModel(selected)}
                                                    options={visionModelDataList?.models?.map((model) => ({
                                                        value: model.id,
                                                        label: model.name
                                                    }))}
                                                    styles={selectStyles}
                                                />

                                                <div className="text-sm text-muted-foreground">
                                                    Using Ollama API endpoint: {process.env.NEXT_PUBLIC_OLLAMA_URL || 'http://ollama:11434'}
                                                </div>
                                            </div>
                                        </div>

                                        <div>
                                            <h3 className="text-sm font-medium mb-2">{t('documentModel')}</h3>
                                            <p className="text-sm text-muted-foreground mb-2">
                                                <span className="block mb-2">
                                                    {t('documentModelDescription')}{' '}
                                                    <a href="https://github.com/DS4SD/docling"
                                                       className="text-primary hover:underline" target="_blank"
                                                       rel="noopener noreferrer">
                                                        {t('documentModelDoclingGithub')}
                                                    </a>
                                                </span>
                                            </p>
                                            <div className="space-y-2">
                                                <Select
                                                    className="basic-single text-sm"
                                                    classNamePrefix="select"
                                                    isSearchable={false}
                                                    value={documentParser}
                                                    onChange={(selected: any) => {
                                                        setDocumentParser(selected)
                                                    }}
                                                    options={documentDataList?.documents?.map((document) => ({
                                                        value: document.name,
                                                        label: document.name
                                                    }))}
                                                    styles={selectStyles}
                                                />

                                                <Select
                                                    className="basic-single text-sm"
                                                    classNamePrefix="select"
                                                    isSearchable={false}
                                                    placeholder={t('selectModel')}
                                                    value={documentParserModel}
                                                    onChange={(selected: any) => {
                                                        setDocumentParserModel(selected)
                                                    }}
                                                    options={documentModelDataList?.models?.map((model: any) => ({
                                                        value: model.id,
                                                        label: model.name
                                                    }))}
                                                    styles={selectStyles}
                                                />
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </>
                    ) : (
                        <div className="h-12 flex items-center justify-center border-t">
                            <Button variant="ghost" onClick={() => setIsOpen(true)}>
                                <ChevronLeft className="h-4 w-4"/>
                            </Button>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}
